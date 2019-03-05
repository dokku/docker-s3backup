#  docker-s3backup

[![dokku/s3backup](http://dockeri.co/image/dokku/s3backup)](https://registry.hub.docker.com/u/dokku/s3backup/)

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

### Advanced Usage

Example with different region, different signature version and call to S3-compatible service (different endpoint url)

```shell
docker run -it \
      -e AWS_ACCESS_KEY_ID=ID \
      -e AWS_SECRET_ACCESS_KEY=KEY \
      -e AWS_DEFAULT_REGION=us-east-1 \
      -e AWS_SIGNATURE_VERSION=s3v4 \
      -e ENDPOINT_URL=https://YOURAPIURL \
      -e BUCKET_NAME=backups \
      -e BACKUP_NAME=backup \
      -v /path/to/backup:/backup dokku/s3backup
```

### Encryption

You can optionally encrypt your backup using GnuPG. To do so, set ENCRYPTION_KEY.

```
docker run -it \
      -e AWS_ACCESS_KEY_ID=ID \
      -e AWS_SECRET_ACCESS_KEY=KEY \
      -e BUCKET_NAME=backups \
      -e BACKUP_NAME=backup \
      -e ENCRYPTION_KEY=your_secret_passphrase
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
