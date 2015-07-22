FROM alpine:latest
RUN apk --update add bash gzip tar go openssl
COPY backup.sh /usr/bin/backup.sh
RUN mkdir -p /go/bin && chmod -R 777 /go
ENV GOPATH /go
ENV PATH /go/bin:$PATH
WORKDIR /go
RUN wget https://github.com/rlmcpherson/s3gof3r/releases/download/v0.4.10/gof3r_0.4.10_linux_amd64.tar.gz ;\
    tar -xzvf gof3r_0.4.10_linux_amd64.tar.gz ;\
    ln -s /go/gof3r_0.4.10_linux_amd64/gof3r /go/bin/gof3r
CMD /usr/bin/backup.sh
