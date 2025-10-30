FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive \
    SRVPORT=4499 \
    PATH="/usr/games:${PATH}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        cowsay \
        fortune-mod \
        netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY wisecow.sh /app/wisecow.sh
RUN chmod +x /app/wisecow.sh

EXPOSE 4499

USER pooja

ENTRYPOINT ["./wisecow.sh"]
