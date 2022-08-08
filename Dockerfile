FROM alpine:3.15.0

# hadolint ignore=DL3018
RUN apk --no-cache add bash gzip groff less python3 py3-pip py3-urllib3 py3-six py3-colorama tar openssl ca-certificates gnupg && \
    pip --no-cache-dir install awscli==1.18.97&& \
    apk --purge -v del py3-pip

COPY backup.sh /usr/bin/backup.sh
COPY gpg.conf /root/.gnupg/gpg.conf
COPY dirmngr.conf /root/.gnupg/dirmngr.conf

RUN chmod 0600 /root/.gnupg

CMD ["/usr/bin/backup.sh"]
