#!/bin/bash
set -e

if [ ! -d "/backup" ]; then
  echo "Please mount a directory to backup with -v /backup:/backup"
	exit 1
fi

#Amazon S3 info
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-null}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-null}

BACKUP_NAME=${BACKUP_NAME:-backup}
BUCKET_NAME=${BUCKET_NAME:-null}

# Add entries as name and file location
TARGET="$BACKUP_NAME /backup/"

BUCKET_HEADERS="$(wget -q -S "https://$BUCKET_NAME.s3.amazonaws.com" 2>&1 || true)"
AWS_REGION="$(echo $BUCKET_HEADERS | grep -Fi x-amz-bucket-region | tr -d '[:space:]' | cut -d':' -f2)"

S3_ENDPOINT="s3-${AWS_REGION}.amazonaws.com"
if [[ "$AWS_REGION" == "us-east-1" ]]; then
  S3_ENDPOINT="s3.amazonaws.com"
fi

#System info
TIMESTAMP=$(date -u "+%Y-%m-%d-%H-%M-%S")

### Run backup to Amazon S3 Bucket
IFS=$'\n'
for i in $TARGET
do
	NAME=$(echo $i | awk {'print $1'})
	TARGET=$(echo $i | awk {'print $2'})
	/bin/tar -czf - $TARGET | /go/bin/gof3r put -b $BUCKET_NAME -k $NAME-$TIMESTAMP.tgz --endpoint "$S3_ENDPOINT"
	if [ "$?" -eq "0" ]; then
		echo "$TIMESTAMP: The backup for $NAME finished successfully."
	else
		echo "Backup of $TARGET has failed. Please look into this and find out what went wrong"
	fi
done
### Finish Amazon backup
