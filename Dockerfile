FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# nextcloudcmd + benötigte Basis-Tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        passwd \
        nextcloud-desktop-cmd \
    && rm -rf /var/lib/apt/lists/*

# Arbeitsverzeichnis für den Sync
WORKDIR /media/nextcloud

# Entrypoint-Skript ins Image kopieren
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Standard-Entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
