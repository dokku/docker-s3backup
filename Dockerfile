FROM alpine:3.5

RUN apk --no-cache  add bash gzip groff less python py-pip tar openssl ca-certificates && \
    pip install awscli==1.11.76 && \
    apk --purge -v del py-pip

COPY backup.sh /usr/bin/backup.sh

CMD /usr/bin/backup.sh
