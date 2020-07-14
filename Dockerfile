FROM alpine:3.12.0

MAINTAINER Jose Diaz-Gonzalez <dokku@josediazgonzalez.com>

RUN apk --no-cache add bash gzip groff less python3 py3-pip tar openssl ca-certificates gnupg && \
    pip --no-cache-dir install awscli==1.16.197 && \
    apk --purge -v del py3-pip

COPY backup.sh /usr/bin/backup.sh
COPY gpg.conf /root/.gnupg/gpg.conf
COPY dirmngr.conf /root/.gnupg/dirmngr.conf

RUN chmod 0600 /root/.gnupg

CMD /usr/bin/backup.sh
