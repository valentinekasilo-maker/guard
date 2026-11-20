#!/usr/bin/env bash
set -e

echo "[INFO] Starting Guard (Pi-hole) for Home Assistant..."

# Ensure core directories exist with proper permissions
mkdir -p /etc/pihole /var/log/pihole /run/pihole /etc/dnsmasq.d /tmp/pihole /var/www/html
chmod 0777 /tmp/pihole 2>/dev/null || true
chown -R pihole:pihole /etc/pihole /var/log/pihole /run/pihole /etc/dnsmasq.d /tmp/pihole /var/www 2>/dev/null || true
chmod -R 0775 /etc/pihole /var/log/pihole /run/pihole /etc/dnsmasq.d 2>/dev/null || true

# Ensure Web Interface files exist in document root and /admin
mkdir -p /var/www/html /var/www/html/admin /etc/pihole/listsCache
if [ -d "/etc/.pihole/web" ]; then
    cp -r /etc/.pihole/web/* /var/www/html/admin/ 2>/dev/null || true
    cp -r /etc/.pihole/web/* /var/www/html/ 2>/dev/null || true
fi
if [ -f "/etc/.pihole/web/index.html" ]; then
    cp /etc/.pihole/web/index.html /var/www/html/index.html
    cp /etc/.pihole/web/index.html /var/www/html/admin/index.html
fi
chown -R pihole:pihole /var/www /etc/pihole/listsCache 2>/dev/null || true
chmod -R 0755 /var/www /etc/pihole/listsCache 2>/dev/null || true

# Always work inside /etc/pihole so relative listsCache paths succeed
cd /etc/pihole

# Parse Home Assistant Add-on options if present
OPTIONS_FILE="/data/options.json"
PASSWORD=""
UPSTREAM_DNS=""
DOMAIN=""

if [ -f "${OPTIONS_FILE}" ]; then
    PASSWORD=$(jq -r '.password // empty' "${OPTIONS_FILE}")
    UPSTREAM_DNS=$(jq -r '.upstream_dns // empty' "${OPTIONS_FILE}")
    DOMAIN=$(jq -r '.domain // empty' "${OPTIONS_FILE}")
fi

# Configure dnsmasq to bind only physical network interfaces and skip loopback (lo)
# This prevents collisions with Home Assistant OS internal resolver on 127.0.0.1:53
cat << 'EOF' > /etc/dnsmasq.d/02-ha-guard.conf
bind-interfaces
except-interface=lo
EOF
chown pihole:pihole /etc/dnsmasq.d/02-ha-guard.conf 2>/dev/null || true

# Populate default adlist if none exists
if [ ! -f "/etc/pihole/adlists.list" ] && [ ! -f "/etc/pihole/gravity.db" ]; then
    echo "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" > /etc/pihole/adlists.list
    chown pihole:pihole /etc/pihole/adlists.list 2>/dev/null || true
fi

# Run prestart script if available
if [ -f "/opt/pihole/pihole-FTL-prestart.sh" ]; then
    sh "/opt/pihole/pihole-FTL-prestart.sh" || true
fi

# Configure Upstream DNS if provided
if [ -n "${UPSTREAM_DNS}" ]; then
    echo "[INFO] Configuring upstream DNS: ${UPSTREAM_DNS}"
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

# Enable reading /etc/dnsmasq.d configs and set DNS listening mode to BIND
pihole-FTL --config misc.etc_dnsmasq_d true || true
pihole-FTL --config dns.listeningMode "BIND" || true

DEFAULT_IFACE=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
if [ -n "${DEFAULT_IFACE}" ]; then
    echo "[INFO] Binding DNS to primary network interface: ${DEFAULT_IFACE}"
    pihole-FTL --config dns.interface "${DEFAULT_IFACE}" || true
fi

# Configure Web Interface Password
if [ -n "${PASSWORD}" ]; then
    echo "[INFO] Setting custom web administration password..."
    pihole-FTL --config webserver.api.password "${PASSWORD}" || true
else
    echo "[INFO] No web password set; web admin password protection disabled."
    pihole-FTL --config webserver.api.password "" || true
fi

# Query Home Assistant Supervisor for dynamic Ingress port if present
INGRESS_PORT=""
if [ -n "${SUPERVISOR_TOKEN}" ]; then
    echo "[INFO] Querying Home Assistant Supervisor for Ingress port..."
    INGRESS_PORT=$(curl -sSL -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" -H "Content-Type: application/json" http://supervisor/addons/self/info 2>/dev/null | jq --raw-output '.data.ingress_port // empty' 2>/dev/null || true)
fi

PORTS="8080o,8088o,4865o"
if [ -n "${INGRESS_PORT}" ] && [ "${INGRESS_PORT}" != "null" ] && [ "${INGRESS_PORT}" != "0" ]; then
    echo "[INFO] Detected Home Assistant Ingress port: ${INGRESS_PORT}"
    PORTS="${INGRESS_PORT}o,${PORTS}"
fi
PORTS="${PORTS},[::]:8080o"

echo "[INFO] Configuring webserver ports: ${PORTS}"
pihole-FTL --config webserver.port "${PORTS}" || true
pihole-FTL --config webserver.paths.webroot "/var/www/html" || true
pihole-FTL --config webserver.paths.webhome "/admin/" || true
pihole-FTL --config webserver.serve_all true || true
pihole-FTL --config webserver.acl "" || true

# Set webserver domain if user specified one in add-on options
if [ -n "${DOMAIN}" ]; then
    echo "[INFO] Configuring webserver domain: ${DOMAIN}"
    pihole-FTL --config webserver.domain "${DOMAIN}" || true
else
    echo "[INFO] Retaining default webserver domain (pi.hole and local interface match)"
fi

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

# Clean up any stale sockets or PID files
rm -f /run/pihole-FTL.pid /run/pihole/FTL.sock /dev/shm/FTL-* 2>/dev/null || true

echo "[INFO] Launching pihole-FTL daemon..."
exec /usr/bin/pihole-FTL -f
