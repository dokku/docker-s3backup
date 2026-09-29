#!/bin/bash

set -eo pipefail
[[ -n "$TRACE" ]] && set -x

# Where the backup is read from: a directory mounted at /backup, or a tar stream on stdin
BACKUP_SOURCE="${BACKUP_SOURCE:-directory}"

case "$BACKUP_SOURCE" in
directory)
  # Check if backup directory exists
  if [[ ! -d "/backup" ]]; then
    echo "Please mount a directory to backup with -v /backup:/backup"
    exit 1
  fi

  # Docker mounts an empty directory when the host path does not exist, which
  # happens when the path is not visible to the docker daemon
  if [[ -z "$(find /backup -mindepth 1 -print -quit)" ]]; then
    echo "The /backup directory is empty. Please check that the mounted host path exists and is visible to the docker daemon."
    exit 1
  fi
  ;;
stdin)
  if [[ -t 0 ]]; then
    echo "Please pipe a tar stream to backup with docker run -i"
    exit 1
  fi
  ;;
*)
  echo "Invalid BACKUP_SOURCE '$BACKUP_SOURCE', must be one of: directory, stdin"
  exit 1
  ;;
esac

# The expected size of the upload in bytes, so that large streams fit in the
# 10,000 parts that S3 allows for a multipart upload
if [[ -n "$S3_EXPECTED_SIZE" ]] && [[ ! "$S3_EXPECTED_SIZE" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid S3_EXPECTED_SIZE '$S3_EXPECTED_SIZE', must be a positive number of bytes"
  exit 1
fi

# Set default values for Amazon S3 info
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-null}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-null}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-null}"

BACKUP_NAME="${BACKUP_NAME:-backup}"
BUCKET_NAME="${BUCKET_NAME:-null}"

# Set default keyserver (Ubuntu keyserver)
KEYSERVER="${KEYSERVER:-hkp://keyserver.ubuntu.com}"

# Set timestamp for backup
TIMESTAMP="$(date -u "+%Y-%m-%d-%H-%M-%S")"

# Build endpoint parameter if endpoint given
if [[ -n "$ENDPOINT_URL" ]]; then
  ENDPOINT_URL_PARAMETER="--endpoint-url=$ENDPOINT_URL"

  # Newer aws cli versions send upload checksums in a trailer without a
  # Content-Length, which S3-compatible services such as Ceph reject. Only send
  # checksums when an operation requires one, unless told otherwise
  export AWS_REQUEST_CHECKSUM_CALCULATION="${AWS_REQUEST_CHECKSUM_CALCULATION:-when_required}"
  export AWS_RESPONSE_CHECKSUM_VALIDATION="${AWS_RESPONSE_CHECKSUM_VALIDATION:-when_required}"
fi

# Add the StorageClass parameter if specified
if [[ -n "$S3_STORAGE_CLASS" ]]; then
  S3_STORAGE_CLASS_PARAMETER="--storage-class=$S3_STORAGE_CLASS"
fi

# Setup AWS signature version if specified
if [[ -n "$AWS_SIGNATURE_VERSION" ]]; then
  aws configure set default.s3.signature_version "$AWS_SIGNATURE_VERSION"
fi

# Setup the multipart upload part size if specified
if [[ -n "$S3_MULTIPART_CHUNKSIZE" ]]; then
  aws configure set default.s3.multipart_chunksize "$S3_MULTIPART_CHUNKSIZE"
fi

# Set target directory for backup
TARGET="backup/"
if [[ "$BACKUP_SOURCE" == "stdin" ]]; then
  TARGET="stdin"
fi

# Set the object key once, so that a failed backup removes the object it uploaded
if [[ -n "$ENCRYPT_WITH_PUBLIC_KEY_ID" ]] || [[ -n "$ENCRYPTION_KEY" ]]; then
  OBJECT_KEY="$BACKUP_NAME-$TIMESTAMP.tgz.gpg"
else
  OBJECT_KEY="$BACKUP_NAME-$TIMESTAMP.tgz"
fi

# Function to estimate the size of the uploaded backup of the target directory.
# GNU tar skips reading file contents when the archive is /dev/null, so this is
# quick. The margin covers gzip and gpg growing data that does not compress
estimate_backup_size() {
  local totals size
  totals="$(tar --create --file /dev/null --totals "$TARGET" 2>&1 >/dev/null)" || return 1
  size="$(sed -n 's/^Total bytes written: \([0-9]*\).*/\1/p' <<<"$totals")"
  [[ -n "$size" ]] || return 1
  echo "$((size + size / 10 + 1048576))"
}

# Function to start checking the tar stream on stdin while it is uploaded
start_stdin_check() {
  STDIN_CHECK_DIR="$(mktemp -d)"
  STDIN_FIFO="$STDIN_CHECK_DIR/stream"
  mkfifo "$STDIN_FIFO"
  tar --list --verbose --file - <"$STDIN_FIFO" >"$STDIN_CHECK_DIR/entries" &
  STDIN_CHECK_PID="$!"
}

# Function to report whether the tar stream on stdin was complete and held a file.
# A writer that dies mid-stream only closes stdin, which would otherwise upload a
# truncated archive as a success
stdin_check_passed() {
  if [[ "$BACKUP_SOURCE" != "stdin" ]]; then
    return 0
  fi

  if ! wait "$STDIN_CHECK_PID"; then
    echo "The tar stream on stdin was incomplete or invalid."
    return 1
  fi

  if ! grep -q '^-' "$STDIN_CHECK_DIR/entries"; then
    echo "The tar stream on stdin contained no files."
    return 1
  fi
}

# Function to create a tar archive of the target directory
create_tar_archive() {
  if [[ "$BACKUP_SOURCE" == "stdin" ]]; then
    tee "$STDIN_FIFO" | gzip
  else
    tar --create --gzip --file - "$TARGET"
  fi
}

# Function to encrypt the input stream
encrypt_stream() {
  if [[ "$1" == "public_key" ]]; then
    gpg --batch --no-tty --quiet --encrypt --always-trust --recipient "$ENCRYPT_WITH_PUBLIC_KEY_ID"
  elif [[ "$1" == "encryption_key" ]]; then
    gpg --batch --no-tty --quiet --symmetric --cipher-algo AES256 --passphrase "$ENCRYPTION_KEY"
  else
    cat
  fi
}

# Function to upload backup to S3
upload_to_s3() {
  # shellcheck disable=SC2086
  aws $ENDPOINT_URL_PARAMETER s3 cp - "s3://$BUCKET_NAME/$OBJECT_KEY" $S3_STORAGE_CLASS_PARAMETER $EXPECTED_SIZE_PARAMETER
}

# Function to remove an upload made from an incomplete tar stream on stdin
remove_failed_upload() {
  if [[ "$BACKUP_SOURCE" != "stdin" ]]; then
    return 0
  fi

  # shellcheck disable=SC2086
  aws $ENDPOINT_URL_PARAMETER s3 rm "s3://$BUCKET_NAME/$OBJECT_KEY" >/dev/null 2>&1 || true
}

# Function to create, encrypt and upload the backup
run_backup() {
  if [[ "$BACKUP_SOURCE" == "stdin" ]]; then
    start_stdin_check
  fi

  if create_tar_archive | encrypt_stream "$1" | upload_to_s3 && stdin_check_passed; then
    echo "$TIMESTAMP: The backup for $BACKUP_NAME finished successfully."
  else
    remove_failed_upload
    echo "Backup of $TARGET has failed. Please investigate the issue."
    exit 1
  fi
}

# Set the expected size of the upload, estimating it for a directory when not given
if [[ -n "$S3_EXPECTED_SIZE" ]]; then
  EXPECTED_SIZE_PARAMETER="--expected-size=$S3_EXPECTED_SIZE"
elif [[ "$BACKUP_SOURCE" == "directory" ]]; then
  if EXPECTED_SIZE="$(estimate_backup_size)"; then
    EXPECTED_SIZE_PARAMETER="--expected-size=$EXPECTED_SIZE"
  else
    echo "Warning: Failed to estimate the size of $TARGET, backups larger than 78 GiB may fail to upload."
  fi
fi

# Perform backup based on encryption method
if [[ -n "$ENCRYPT_WITH_PUBLIC_KEY_ID" ]]; then
  if gpg --quiet --keyserver "$KEYSERVER" --recv-keys "$ENCRYPT_WITH_PUBLIC_KEY_ID"; then
    run_backup "public_key"
  else
    echo "Error: Failed to retrieve the public key from the keyserver."
    exit 1
  fi
elif [[ -n "$ENCRYPTION_KEY" ]]; then
  run_backup "encryption_key"
else
  run_backup "no_encryption"
fi
