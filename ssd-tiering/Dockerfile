FROM alpine:latest

RUN apk add --no-cache bash coreutils findutils

COPY scripts/ssd-cleanup.sh /usr/local/bin/ssd-cleanup.sh
RUN chmod +x /usr/local/bin/ssd-cleanup.sh

# Run cleanup every 30 minutes
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]