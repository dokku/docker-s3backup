FROM alpine:3.21.1

# hadolint ignore=DL3018
RUN apk --no-cache add bash gzip groff less aws-cli tar openssl ca-certificates gnupg

COPY backup.sh /usr/bin/backup.sh
COPY gpg.conf /root/.gnupg/gpg.conf
COPY dirmngr.conf /root/.gnupg/dirmngr.conf

RUN chmod 0600 /root/.gnupg

CMD ["/usr/bin/backup.sh"]
