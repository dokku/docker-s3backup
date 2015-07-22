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

#System info
TIMESTAMP=$(date +"%Y.%m.%d")

### Run backup to Amazon S3 Bucket
IFS=$'\n'
for i in $TARGET
do
	NAME=$(echo $i | awk {'print $1'})
	TARGET=$(echo $i | awk {'print $2'})
	/bin/tar -czf - $TARGET | /go/bin/gof3r put -b $BUCKET_NAME -k $NAME-$TIMESTAMP.tgz
	if [ "$?" -eq "0" ]; then
		echo "$TIMESTAMP: The backup for $NAME finished successfully."
	else
		echo "Backup of $TARGET has failed. Please look into this and find out what went wrong"
	fi
done
### Finish Amazon backup
