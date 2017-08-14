#!/bin/bash
set -e

if [ ! -d "/backup" ]; then
	echo "Please mount a directory to backup with -v /backup:/backup"
	exit 1
fi

#Amazon S3 info
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-null}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-null}
AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-null}

BACKUP_NAME=${BACKUP_NAME:-backup}
BUCKET_NAME=${BUCKET_NAME:-null}

# Add entries as name and file location
TARGET="$BACKUP_NAME backup/"

#System info
TIMESTAMP=$(date -u "+%Y-%m-%d-%H-%M-%S")

### Build endpoint parameter if endpoint given
if [ -n "$ENDPOINT_URL" ]; then
	ENDPOINT_URL_PARAMETER="--endpoint-url=$ENDPOINT_URL"
fi

### Setup AWS signature version if specified
if [ -n "$AWS_SIGNATURE_VERSION" ]; then
	aws configure set default.s3.signature_version $AWS_SIGNATURE_VERSION
fi

### Run backup to Amazon S3 Bucket
IFS=$'\n'
for i in $TARGET
do
	NAME=$(echo $i | awk {'print $1'})
	TARGET=$(echo $i | awk {'print $2'})
	/bin/tar -czf - $TARGET | aws $ENDPOINT_URL_PARAMETER s3 cp - s3://$BUCKET_NAME/$NAME-$TIMESTAMP.tgz
	if [ "$?" -eq "0" ]; then
		echo "$TIMESTAMP: The backup for $NAME finished successfully."
	else
		echo "Backup of $TARGET has failed. Please look into this and find out what went wrong"
	fi
done
### Finish Amazon backup
