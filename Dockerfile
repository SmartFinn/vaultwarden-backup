ARG ARCH=
FROM ${ARCH}alpine:latest

RUN apk add --no-cache \
    gnupg \
    sqlite \
    busybox-suid \
    su-exec \
    tzdata

COPY entrypoint.sh /
COPY backup.sh /app/

ENTRYPOINT ["/entrypoint.sh"]
