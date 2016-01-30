[![nodesource/node](http://dockeri.co/image/novacoast/s3backup)](https://registry.hub.docker.com/u/novacoast/s3backup/)

# Info
Docker image that creates and streams a tar backup of a host volume to Amazon S3 storage.

+ Lightweight: Based on the [Alpine](https://github.com/gliderlabs/docker-alpine) base image
+ Fast: Backups are streamed directly to S3 with [s3gof3r](https://github.com/rlmcpherson/s3gof3r)

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

Then run the image, specifying your AWS credentials, bucket name, and backup path.

```
docker run -it \
      -e AWS_ACCESS_KEY_ID=ID \
      -e AWS_SECRET_ACCESS_KEY=KEY \
      -e BUCKET_NAME=backups \
      -e BACKUP_NAME=backup \
      -v /path/to/backup:/backup s3backup
```
