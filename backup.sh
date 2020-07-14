#!/bin/bash
set -eo pipefail
[[ -n "$TRACE" ]] && set -x

if [[ ! -d "/backup" ]]; then
  echo "Please mount a directory to backup with -v /backup:/backup"
  exit 1
fi

#Amazon S3 info
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-null}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-null}
AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-null}
S3_STORAGE_CLASS=${S3_STORAGE_CLASS:-STANDARD}

BACKUP_NAME=${BACKUP_NAME:-backup}
BUCKET_NAME=${BUCKET_NAME:-null}

#System info
TIMESTAMP=$(date -u "+%Y-%m-%d-%H-%M-%S")

### Build endpoint parameter if endpoint given
if [[ -n "$ENDPOINT_URL" ]]; then
  ENDPOINT_URL_PARAMETER="--endpoint-url=$ENDPOINT_URL"
fi

### Setup AWS signature version if specified
if [[ -n "$AWS_SIGNATURE_VERSION" ]]; then
  aws configure set default.s3.signature_version "$AWS_SIGNATURE_VERSION"
fi

### Run backup to Amazon S3 Bucket
TARGET="backup/"
if [[ -n "$ENCRYPTION_KEY" ]]; then
  # shellcheck disable=SC2086
  /bin/tar -czf - "$TARGET" | gpg --batch --no-tty -q -c --passphrase "$ENCRYPTION_KEY" | aws $ENDPOINT_URL_PARAMETER s3 cp - "s3://$BUCKET_NAME/$BACKUP_NAME-$TIMESTAMP.tgz.gpg" --storage-class $S3_STORAGE_CLASS
else
  # shellcheck disable=SC2086
  /bin/tar -czf - "$TARGET" | aws $ENDPOINT_URL_PARAMETER s3 cp - "s3://$BUCKET_NAME/$BACKUP_NAME-$TIMESTAMP.tgz" --storage-class $S3_STORAGE_CLASS
fi

# shellcheck disable=SC2181
if [[ "$?" -eq "0" ]]; then
  echo "$TIMESTAMP: The backup for $BACKUP_NAME finished successfully."
else
  echo "Backup of $TARGET has failed. Please look into this and find out what went wrong"
fi
### Finish Amazon backup
