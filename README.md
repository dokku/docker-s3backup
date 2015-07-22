# Info
Docker image that utilizes [https://github.com/rlmcpherson/s3gof3r](s3gof3r) to stream a tar backup to Amazon S3 storage.

+ Lightweight: Based on [https://github.com/gliderlabs/docker-alpine](alpine) base image
+ Fast: Backups are streamed directly to S3

# Usage
Run the automated build, specifying your AWS credentials, bucket name, and backup path.

```
docker run -it \
      -e AWS_ACCESS_KEY_ID=ID \
      -e AWS_SECRET_ACCESS_KEY=KEY \
      -e BUCKET_NAME=backups \
      -e BACKUP_NAME=backup \
      -v /path/to/backup:/backup novacoast/s3backup
```

## Build Locally
First, build the image.

```
docker build -t s3backup .
```

```
docker run -it \
      -e AWS_ACCESS_KEY_ID=ID \
      -e AWS_SECRET_ACCESS_KEY=KEY \
      -e BUCKET_NAME=backups \
      -e BACKUP_NAME=backup \
      -v /path/to/backup:/backup s3backup
```
