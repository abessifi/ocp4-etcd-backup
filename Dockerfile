FROM registry.access.redhat.com/ubi8/python-38

USER root

WORKDIR /usr/src/app

COPY entrypoint.sh .

RUN wget -O /tmp/mc https://dl.min.io/client/mc/release/linux-amd64/mc && \
    chmod +x /tmp/mc && \
    mv /tmp/mc /usr/local/bin/ && \
    mkdir -p /root/.mc && \
    chmod +x entrypoint.sh

CMD "entrypoint.sh"
