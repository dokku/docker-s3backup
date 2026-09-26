#!/usr/bin/env bats
# Runs the image against a local s3 server and checks what it uploads.

bats_require_minimum_version 1.5.0
bats_load_library bats-support
bats_load_library bats-assert

# the image under test, built from this checkout
IMAGE="${IMAGE:-dokku/s3backup:test}"

# an s3 server that runs from a single container
S3_IMAGE="chrislusf/seaweedfs:4.47"

NETWORK="s3backup-test"
S3_CONTAINER="s3backup-test-s3"
ENDPOINT_URL="http://$S3_CONTAINER:8333"
BUCKET_NAME="backups"
ACCESS_KEY_ID="s3backup"
SECRET_ACCESS_KEY="s3backup-secret"

# runs the aws cli from the image under test against the s3 server
aws_cli() {
  docker container run --rm -i --network "$NETWORK" --entrypoint aws \
    -e AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID" \
    -e AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY" \
    -e AWS_DEFAULT_REGION=us-east-1 \
    "$IMAGE" --endpoint-url "$ENDPOINT_URL" "$@"
}

# runs the image under test against the s3 server, with any extra docker flags
# ahead of the image
run_backup() {
  docker container run --rm --network "$NETWORK" \
    -e AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID" \
    -e AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY" \
    -e AWS_DEFAULT_REGION=us-east-1 \
    -e ENDPOINT_URL="$ENDPOINT_URL" \
    -e BUCKET_NAME="$BUCKET_NAME" \
    -e BACKUP_NAME=test \
    "$@" "$IMAGE"
}

# runs the image under test in stdin mode, reading a file as the stream
run_backup_from() {
  local stream="$1"
  shift
  run_backup -i -e BACKUP_SOURCE=stdin "$@" <"$stream"
}

# a tar stream of backup/, as a file. Without the extended attributes and
# resource forks macOS adds, so the stream holds only what the test put there
make_backup_tar() {
  COPYFILE_DISABLE=1 tar --no-xattrs -C "$BATS_TEST_TMPDIR" -cf "$BATS_TEST_TMPDIR/backup.tar" backup
}

# the keys in the bucket, one per line
bucket_keys() {
  aws_cli s3 ls "s3://$BUCKET_NAME/" | awk '{ print $4 }'
}

# downloads the only object in the bucket to a file
download_backup() {
  local key
  key="$(bucket_keys)"
  [[ -n "$key" ]] || fail "no backup was uploaded"
  [[ "$(wc -l <<<"$key")" -eq 1 ]] || fail "expected one backup, got: $key"
  aws_cli s3 cp "s3://$BUCKET_NAME/$key" - >"$1"
}

assert_bucket_empty() {
  local keys
  keys="$(bucket_keys)"
  [[ -z "$keys" ]] || fail "expected no backup to be left behind, got: $keys"
}

# a directory holding a file with known contents, as backup/ would be mounted
make_backup_dir() {
  mkdir -p "$BATS_TEST_TMPDIR/backup"
  head -c 1048576 /dev/urandom >"$BATS_TEST_TMPDIR/backup/export"
}

setup_file() {
  docker network create "$NETWORK" >/dev/null
  docker container run -d --name "$S3_CONTAINER" --network "$NETWORK" \
    -e AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID" \
    -e AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY" \
    "$S3_IMAGE" server -s3 -dir=/data >/dev/null

  local attempt
  for attempt in $(seq 1 60); do
    if aws_cli s3 mb "s3://$BUCKET_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "the s3 server never answered" >&2
  return 1
}

teardown_file() {
  docker container rm -f "$S3_CONTAINER" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
}

setup() {
  aws_cli s3 rm --recursive "s3://$BUCKET_NAME/" >/dev/null
}

@test "a mounted directory is uploaded" {
  make_backup_dir

  run run_backup -v "$BATS_TEST_TMPDIR/backup:/backup"
  assert_success
  assert_output --partial "The backup for test finished successfully."

  download_backup "$BATS_TEST_TMPDIR/backup.tgz"
  mkdir "$BATS_TEST_TMPDIR/extracted"
  tar -xzf "$BATS_TEST_TMPDIR/backup.tgz" -C "$BATS_TEST_TMPDIR/extracted"
  cmp "$BATS_TEST_TMPDIR/backup/export" "$BATS_TEST_TMPDIR/extracted/backup/export"
}

@test "a missing directory is refused" {
  run run_backup
  assert_failure
  assert_output --partial "Please mount a directory to backup"
  assert_bucket_empty
}

@test "an empty directory is refused rather than uploaded" {
  mkdir "$BATS_TEST_TMPDIR/empty"

  run run_backup -v "$BATS_TEST_TMPDIR/empty:/backup"
  assert_failure
  assert_output --partial "The /backup directory is empty"
  assert_bucket_empty
}

@test "an unknown backup source is refused" {
  run run_backup -e BACKUP_SOURCE=elsewhere
  assert_failure
  assert_output --partial "Invalid BACKUP_SOURCE 'elsewhere'"
  assert_bucket_empty
}

@test "a tar stream on stdin is uploaded with the same layout" {
  make_backup_dir
  make_backup_tar

  run run_backup_from "$BATS_TEST_TMPDIR/backup.tar"
  assert_success
  assert_output --partial "The backup for test finished successfully."

  download_backup "$BATS_TEST_TMPDIR/backup.tgz"
  mkdir "$BATS_TEST_TMPDIR/extracted"
  tar -xzf "$BATS_TEST_TMPDIR/backup.tgz" -C "$BATS_TEST_TMPDIR/extracted"
  cmp "$BATS_TEST_TMPDIR/backup/export" "$BATS_TEST_TMPDIR/extracted/backup/export"
}

@test "a tar stream on stdin is encrypted with a passphrase" {
  make_backup_dir
  make_backup_tar

  run run_backup_from "$BATS_TEST_TMPDIR/backup.tar" -e ENCRYPTION_KEY=passphrase
  assert_success

  run bucket_keys
  assert_output --regexp '^test-.*\.tgz\.gpg$'

  download_backup "$BATS_TEST_TMPDIR/backup.tgz.gpg"
  docker container run --rm -i --entrypoint gpg "$IMAGE" \
    --batch --quiet --passphrase passphrase --decrypt \
    <"$BATS_TEST_TMPDIR/backup.tgz.gpg" >"$BATS_TEST_TMPDIR/backup.tgz"
  mkdir "$BATS_TEST_TMPDIR/extracted"
  tar -xzf "$BATS_TEST_TMPDIR/backup.tgz" -C "$BATS_TEST_TMPDIR/extracted"
  cmp "$BATS_TEST_TMPDIR/backup/export" "$BATS_TEST_TMPDIR/extracted/backup/export"
}

@test "a truncated tar stream on stdin fails and leaves nothing behind" {
  make_backup_dir
  make_backup_tar
  head -c 524288 "$BATS_TEST_TMPDIR/backup.tar" >"$BATS_TEST_TMPDIR/truncated.tar"

  run run_backup_from "$BATS_TEST_TMPDIR/truncated.tar"
  assert_failure
  assert_output --partial "The tar stream on stdin was incomplete or invalid."
  assert_bucket_empty
}

@test "a tar stream on stdin with no files fails and leaves nothing behind" {
  mkdir "$BATS_TEST_TMPDIR/backup"
  make_backup_tar

  run run_backup_from "$BATS_TEST_TMPDIR/backup.tar"
  assert_failure
  assert_output --partial "The tar stream on stdin contained no files."
  assert_bucket_empty
}

@test "an empty stdin fails and leaves nothing behind" {
  run run_backup_from /dev/null
  assert_failure
  assert_output --partial "The tar stream on stdin was incomplete or invalid."
  assert_bucket_empty
}
