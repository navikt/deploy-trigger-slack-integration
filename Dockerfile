FROM alpine

COPY entrypoint.sh /entrypoint.sh

RUN apk add --no-cache bash curl jq

ENTRYPOINT ["/entrypoint.sh"]