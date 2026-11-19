#!/usr/bin/env bash
set -e

echo "[INFO] Starting Guard (Pi-hole) for Home Assistant..."

# Ensure core directories exist with proper permissions
mkdir -p /etc/pihole /var/log/pihole /run/pihole /etc/dnsmasq.d
chown -R pihole:pihole /etc/pihole /var/log/pihole /run/pihole /etc/dnsmasq.d 2>/dev/null || true

# Parse Home Assistant Add-on options if present
OPTIONS_FILE="/data/options.json"
PASSWORD=""
UPSTREAM_DNS=""

if [ -f "${OPTIONS_FILE}" ]; then
    PASSWORD=$(jq -r '.password // empty' "${OPTIONS_FILE}")
    UPSTREAM_DNS=$(jq -r '.upstream_dns // empty' "${OPTIONS_FILE}")
fi

# Run prestart script if available
if [ -f "/opt/pihole/pihole-FTL-prestart.sh" ]; then
    sh "/opt/pihole/pihole-FTL-prestart.sh" || true
fi

# Configure Upstream DNS if provided
if [ -n "${UPSTREAM_DNS}" ]; then
    echo "[INFO] Configuring upstream DNS: ${UPSTREAM_DNS}"
    # Convert semicolon or comma separated list to JSON array
    JSON_UPSTREAMS=$(echo "${UPSTREAM_DNS}" | awk -F'[,;]' '{
        printf "["
        for(i=1; i<=NF; i++) {
            gsub(/^[ \t]+|[ \t]+$/, "", $i);
            if(length($i) > 0) {
                if(i > 1) printf ", ";
                printf "\"%s\"", $i;
            }
        }
        printf "]"
    }')
    pihole-FTL --config dns.upstreams "${JSON_UPSTREAMS}" || true
fi

# Configure Web Interface Password
if [ -n "${PASSWORD}" ]; then
    echo "[INFO] Setting custom web administration password..."
    pihole-FTL --config webserver.api.password "${PASSWORD}" || true
else
    echo "[INFO] No web password set; web admin password protection disabled."
    pihole-FTL --config webserver.api.password "" || true
fi

# Ensure web server listens on port 8080 on all interfaces
pihole-FTL --config webserver.port 8080 || true
pihole-FTL --config webserver.interface "" || true

# Initialize Gravity database if missing
if [ ! -f "/etc/pihole/gravity.db" ]; then
    echo "[INFO] Initializing Gravity database and default adlists..."
    /opt/pihole/gravity.sh || true
fi

# Setup graceful shutdown handler
cleanup() {
    echo "[INFO] Stopping Guard..."
    FTL_PID=$(cat /run/pihole-FTL.pid 2>/dev/null || true)
    if [ -n "${FTL_PID}" ] && kill -0 "${FTL_PID}" 2>/dev/null; then
        kill -TERM "${FTL_PID}"
        wait "${FTL_PID}" 2>/dev/null || true
    fi
    exit 0
}
trap cleanup SIGTERM SIGINT

echo "[INFO] Launching pihole-FTL daemon..."
exec /usr/bin/pihole-FTL -f
