FROM alpine

COPY entrypoint.sh /entrypoint.sh

RUN apk add --no-cache bash

ENTRYPOINT ["/entrypoint.sh"]