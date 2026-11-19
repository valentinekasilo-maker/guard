ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base-debian:bookworm
FROM ${BUILD_FROM}

ENV DEBIAN_FRONTEND=noninteractive \
    PIHOLE_DOCKER=true \
    GITDIR=/etc/.pihole \
    SCRIPTDIR=/opt/pihole \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/pihole

# Install required runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    bind9-dnsutils \
    iproute2 \
    procps \
    psmisc \
    util-linux \
    libcap2-bin \
    sqlite3 \
    coreutils \
    cron \
    sed \
    grep \
    gawk \
    && rm -rf /var/lib/apt/lists/*

# Create pihole system user and directories
RUN groupadd -g 999 pihole 2>/dev/null || true \
    && useradd -u 999 -g pihole -d /etc/pihole -s /usr/sbin/nologin pihole 2>/dev/null || true \
    && mkdir -p /etc/pihole /var/log/pihole /opt/pihole /etc/.pihole /run/pihole /etc/dnsmasq.d \
    && chown -R pihole:pihole /etc/pihole /var/log/pihole

# Copy repository code
COPY . /etc/.pihole/

# Install scripts into /opt/pihole and CLI wrapper
RUN cp -r /etc/.pihole/advanced/Scripts/* /opt/pihole/ 2>/dev/null || true \
    && cp /etc/.pihole/gravity.sh /opt/pihole/ \
    && cp /etc/.pihole/pihole /opt/pihole/ \
    && cp /etc/.pihole/advanced/Templates/pihole-FTL-prestart.sh /opt/pihole/ 2>/dev/null || true \
    && cp /etc/.pihole/advanced/Templates/pihole-FTL-poststop.sh /opt/pihole/ 2>/dev/null || true \
    && ln -sf /opt/pihole/pihole /usr/local/bin/pihole \
    && chmod +x /opt/pihole/* /usr/local/bin/pihole

# Download target architecture FTL binary
ARG TARGETARCH
RUN set -ex; \
    ARCH="${TARGETARCH}"; \
    if [ -z "$ARCH" ]; then \
        ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m); \
    fi; \
    case "$ARCH" in \
        "amd64"|"x86_64") FTL_ARCH="amd64" ;; \
        "arm64"|"aarch64") FTL_ARCH="arm64" ;; \
        "armv7"|"armhf"|"arm/v7") FTL_ARCH="armv7" ;; \
        *) FTL_ARCH="amd64" ;; \
    esac; \
    echo "Downloading pihole-FTL for $FTL_ARCH..."; \
    curl -sSL --fail "https://github.com/pi-hole/ftl/releases/latest/download/pihole-FTL-${FTL_ARCH}" -o /usr/bin/pihole-FTL; \
    chmod 0755 /usr/bin/pihole-FTL; \
    setcap CAP_NET_BIND_SERVICE,CAP_NET_RAW,CAP_NET_ADMIN,CAP_SYS_NICE,CAP_CHOWN,CAP_SYS_TIME+eip /usr/bin/pihole-FTL || true

# Entrypoint script
COPY rootfs/run.sh /run.sh
RUN chmod +x /run.sh

EXPOSE 53/tcp 53/udp 80/tcp

ENTRYPOINT ["/run.sh"]
