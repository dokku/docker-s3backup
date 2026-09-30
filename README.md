# docker-s3backup

[![dokku/s3backup](http://dockeri.co/image/dokku/s3backup)](https://hub.docker.com/r/dokku/s3backup/)

## Info

Docker image that creates and streams a tar backup of a host volume to Amazon S3 storage.

+ Lightweight: Based on the [Alpine](https://github.com/gliderlabs/docker-alpine) base image
+ Fast: Backups are streamed directly to S3 with [awscli](https://docs.aws.amazon.com/cli/latest/reference/s3/cp.html)
+ Versatile: Can also be used with selfhosted S3-compatible services like [minio](https://github.com/minio/minio)

## Usage

Run the automated build, specifying your AWS credentials, bucket name, and backup path.

```shell
docker run -it \
      -e AWS_ACCESS_KEY_ID=ID \
      -e AWS_SECRET_ACCESS_KEY=KEY \
      -e BUCKET_NAME=backups \
      -e BACKUP_NAME=backup \
      -v /path/to/backup:/backup dokku/s3backup
```

The backup fails if `/backup` is empty. Docker mounts an empty directory when the host path does not exist, which
happens when the path is not visible to the docker daemon, such as when `docker run` is called from inside another
container.

### Streaming from stdin

Set `BACKUP_SOURCE=stdin` to read the backup from stdin instead of from a mounted directory. Stdin must be an
uncompressed tar stream, and the uploaded object has the same `.tgz` layout as a backup of a mounted directory. Nothing
is mounted, so this works wherever `docker run` is called from.

```shell
tar --create --file - backup/ | docker run -i \
      -e AWS_ACCESS_KEY_ID=ID \
      -e AWS_SECRET_ACCESS_KEY=KEY \
      -e BUCKET_NAME=backups \
      -e BACKUP_NAME=backup \
      -e BACKUP_SOURCE=stdin \
      dokku/s3backup
```

The stream is checked while it is uploaded. If it is incomplete, invalid, or holds no files, the uploaded object is
removed and the backup fails.

### Large backups

Backups are uploaded to S3 in parts, and S3 allows at most 10,000 parts per upload. The aws cli uses 8 MiB parts by
default, so an upload larger than about 78 GiB fails unless the part size is raised.

Backups of a mounted directory estimate their size before uploading and raise the part size to fit. The size of a
stream on stdin is not known ahead of time, so a stream larger than about 78 GiB needs `S3_EXPECTED_SIZE` set to its
size in bytes. An overestimate is fine. `S3_EXPECTED_SIZE` also replaces the estimate for a mounted directory.

```shell
tar --create --file - backup/ | docker run -i \
      -e AWS_ACCESS_KEY_ID=ID \
      -e AWS_SECRET_ACCESS_KEY=KEY \
      -e BUCKET_NAME=backups \
      -e BACKUP_NAME=backup \
      -e BACKUP_SOURCE=stdin \
      -e S3_EXPECTED_SIZE=536870912000 \
      dokku/s3backup
```

The starting part size can also be set with `S3_MULTIPART_CHUNKSIZE`, such as `S3_MULTIPART_CHUNKSIZE=64MB`. The aws
cli still raises the part size when `S3_EXPECTED_SIZE` or the estimate needs larger parts. Larger parts use more
memory while uploading.

### Object key

Backups are uploaded to `$BACKUP_NAME-<timestamp>.tgz`, or `$BACKUP_NAME-<timestamp>.tgz.gpg` when encrypted, where the
timestamp is the UTC time the backup started as `%Y-%m-%d-%H-%M-%S`. `BUCKET_NAME` may end in a path to upload under,
such as `BUCKET_NAME=backups/postgres`.

Set `BACKUP_TIMESTAMP=false` to upload every backup to the same key, `$BACKUP_NAME.tgz` or `$BACKUP_NAME.tgz.gpg`, so
that [bucket versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html) and lifecycle rules keep
and rotate the backups. Without versioning, each backup replaces the one before it.

```shell
tar --create --file - backup/ | docker run -i \
      -e AWS_ACCESS_KEY_ID=ID \
      -e AWS_SECRET_ACCESS_KEY=KEY \
      -e BUCKET_NAME=backups \
      -e BACKUP_NAME=backup \
      -e BACKUP_SOURCE=stdin \
      -e BACKUP_TIMESTAMP=false \
      dokku/s3backup
```

When a backup from stdin to a fixed key fails, only an object it uploaded is removed. On a versioned bucket that makes
the previous backup current again, and an upload that never finished leaves the previous backup in place either way.

### Advanced Usage

Example with different region, different S3 storage class, different signature version and call to S3-compatible
service (different endpoint url)

```shell
docker run -it \
      -e AWS_ACCESS_KEY_ID=ID \
      -e AWS_SECRET_ACCESS_KEY=KEY \
      -e AWS_DEFAULT_REGION=us-east-1 \
      -e AWS_SIGNATURE_VERSION=s3v4 \
      -e S3_STORAGE_CLASS=STANDARD_IA \
      -e ENDPOINT_URL=https://YOURAPIURL \
      -e BUCKET_NAME=backups \
      -e BACKUP_NAME=backup \
      -v /path/to/backup:/backup dokku/s3backup
```

Newer aws cli versions send upload checksums in a trailer without a `Content-Length`, which S3-compatible services such
as Ceph reject with `MissingContentLength`. When `ENDPOINT_URL` is set, `AWS_REQUEST_CHECKSUM_CALCULATION` and
`AWS_RESPONSE_CHECKSUM_VALIDATION` default to `when_required`, so checksums are only sent when an operation requires
one. Either can be set to override the default. Without `ENDPOINT_URL`, the aws cli defaults apply.

### Encryption

You can optionally encrypt your backup using GnuPG. To do so, set ENCRYPTION_KEY. This would encrypt the backup with the
passphrase "your_secret_passphrase". The cypher algorithm used is AES256.

```shell
docker run -it \
      -e AWS_ACCESS_KEY_ID=ID \
      -e AWS_SECRET_ACCESS_KEY=KEY \
      -e BUCKET_NAME=backups \
      -e BACKUP_NAME=backup \
      -e ENCRYPTION_KEY=your_secret_passphrase
      -v /path/to/backup:/backup dokku/s3backup
```

You can also use a GPG public key to encrypt the backup. To do so, set ENCRYPTION_KEY to the public key. This would
encrypt the backup with the public key. **The backup can only be decrypted with the corresponding private key**, making
it impossible to encrypt your data even if the backups and all the configuration files are compromised.

```shell
docker run -it \
      -e AWS_ACCESS_KEY_ID=ID \
      -e AWS_SECRET_ACCESS_KEY=KEY \
      -e BUCKET_NAME=backups \
      -e BACKUP_NAME=backup \
      -e ENCRYPT_WITH_PUBLIC_KEY_ID=public_key_id \
      -v /path/to/backup:/backup dokku/s3backup
```

In the above command, replace `public_key_id` with the ID (or, even better, the fingerprint) of your GPG public key. The
backup will be encrypted using this
public key and can only be decrypted with the corresponding private key. Please note that the public key must be
available on the keyserver specified by the KEYSERVER environment variable. By default, this is set
to `hkp://keyserver.ubuntu.com` and can be overridden by setting the KEYSERVER environment variable:

```shell
docker run -it \
      -e AWS_ACCESS_KEY_ID=ID \
      -e AWS_SECRET_ACCESS_KEY=KEY \
      -e BUCKET_NAME=backups \
      -e BACKUP_NAME=backup \
      -e ENCRYPT_WITH_PUBLIC_KEY_ID=public_key_id \
      -e KEYSERVER=hkp://pgp.mit.edu \
      -v /path/to/backup:/backup dokku/s3backup
```

## Building

First, build the image.

```shell
docker build -t s3backup .
```

Then run the image, specifying your AWS credentials, bucket name, and backup path.

```shell
docker run -it \
      -e AWS_ACCESS_KEY_ID=ID \
      -e AWS_SECRET_ACCESS_KEY=KEY \
      -e BUCKET_NAME=backups \
      -e BACKUP_NAME=backup \
      -v /path/to/backup:/backup s3backup
```

## Testing

The tests are written in [bats](https://github.com/bats-core/bats-core) and run the image against a local S3 server.
They load [bats-support](https://github.com/bats-core/bats-support) and
[bats-assert](https://github.com/bats-core/bats-assert) from `BATS_LIB_PATH`.

```shell
docker build -t dokku/s3backup:test .
IMAGE=dokku/s3backup:test bats tests
```
