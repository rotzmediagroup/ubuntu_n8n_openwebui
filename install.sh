#!/usr/bin/env bash
# One-shot installer for n8n + Open WebUI on Ubuntu 22.04/24.04
# - Installs Docker Engine + Compose plugin
# - Creates persistent storage & docker-compose stack
# - Opens UFW ports 5678 (n8n) and 8080 (Open WebUI) if UFW is active
# - Creates /root/update_containers.sh for easy updates
# - Sets N8N_SECURE_COOKIE=false by default (so HTTP works immediately)
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

### --- Helpers ---
log() { echo -e "\e[1;32m[+] $*\e[0m"; }
warn() { echo -e "\e[1;33m[!] $*\e[0m"; }
err() { echo -e "\e[1;31m[✗] $*\e[0m" >&2; }
need_root() { [ "$(id -u)" -eq 0 ] || { err "Run this script as root (use sudo)."; exit 1; }; }

### --- Preflight ---
need_root

if ! command -v lsb_release >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y lsb-release
fi

UBU_CODENAME="$(lsb_release -cs || echo "jammy")"
case "$UBU_CODENAME" in
  jammy|noble) : ;;
  *) warn "This script targets Ubuntu 22.04 (jammy) and 24.04 (noble). Detected '$UBU_CODENAME'. Proceeding anyway...";;
esac

# Detect server IP (best-effort)
detect_ip() {
  if command -v ip >/dev/null 2>&1; then
    ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -n1
  fi
}
SERVER_IP="${SERVER_IP:-$(detect_ip || true)}"
SERVER_IP="${SERVER_IP:-localhost}"

# Timezone (default to Europe/Amsterdam if system TZ missing)
TZ_VAL="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
TZ_VAL="${TZ_VAL:-Europe/Amsterdam}"

log "Using timezone: $TZ_VAL"
log "Detected server IP: $SERVER_IP"

### --- Install prerequisites and Docker ---
log "Installing prerequisites..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg apt-transport-https software-properties-common

log "Setting up Docker repository..."
install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $UBU_CODENAME stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
log "Installing Docker Engine and Compose plugin..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log "Enabling and starting Docker service..."
systemctl enable --now docker

# Sanity checks
docker --version >/dev/null 2>&1 || { err "Docker not installed correctly."; exit 1; }
docker compose version >/dev/null 2>&1 || { err "Docker Compose plugin not found."; exit 1; }

### --- Create stack directories and files ---
STACK_DIR="/opt/stack"
N8N_DATA_DIR="/opt/n8n"
OWUI_DATA_DIR="/opt/open-webui"
NETWORK_NAME="app_net"

log "Creating directories for persistent data..."
mkdir -p "$STACK_DIR" "$N8N_DATA_DIR" "$OWUI_DATA_DIR"
chmod 755 "$STACK_DIR" "$N8N_DATA_DIR" "$OWUI_DATA_DIR"
# Ensure n8n can write to its data directory (container runs as UID 1000)
chown -R 1000:1000 "$N8N_DATA_DIR"

ENV_FILE="$STACK_DIR/.env"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"

log "Writing environment file: $ENV_FILE"
cat > "$ENV_FILE" <<EOF
# Global
TZ=$TZ_VAL

# n8n
N8N_PORT=5678
N8N_BASIC_AUTH_ACTIVE=false
N8N_HOST=$SERVER_IP
N8N_PROTOCOL=http
N8N_EDITOR_BASE_URL=http://$SERVER_IP:5678
WEBHOOK_URL=http://$SERVER_IP:5678/
# Allow HTTP access without HTTPS by default (you can switch to true after enabling HTTPS)
N8N_SECURE_COOKIE=false
EOF

log "Creating Docker network (if not exists): $NETWORK_NAME"
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  docker network create "$NETWORK_NAME"
fi

log "Writing Docker Compose file: $COMPOSE_FILE"
cat > "$COMPOSE_FILE" <<'YAML'
services:
  n8n:
    image: docker.io/n8nio/n8n:latest
    container_name: n8n
    user: "1000:1000"
    restart: unless-stopped
    env_file:
      - ./.env
    environment:
      - TZ=${TZ}
      - N8N_PORT=${N8N_PORT}
      - N8N_HOST=${N8N_HOST}
      - N8N_PROTOCOL=${N8N_PROTOCOL}
      - N8N_EDITOR_BASE_URL=${N8N_EDITOR_BASE_URL}
      - WEBHOOK_URL=${WEBHOOK_URL}
      - DB_TYPE=sqlite
      - GENERIC_TIMEZONE=${TZ}
      - N8N_SECURE_COOKIE=${N8N_SECURE_COOKIE}
    ports:
      - "${N8N_PORT}:5678"
    volumes:
      - /opt/n8n:/home/node/.n8n
    networks:
      - app_net

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: unless-stopped
    environment:
      - TZ=${TZ}
      # - PORT=8080   # change only if you map a different host port
    ports:
      - "8080:8080"
    volumes:
      - /opt/open-webui:/app/backend/data
    networks:
      - app_net

networks:
  app_net:
    external: true
YAML

### --- UFW rules (if UFW enabled) ---
if command -v ufw >/dev/null 2>&1; then
  if ufw status | grep -qi "Status: active"; then
    log "UFW is active. Opening ports 5678 (n8n) and 8080 (Open WebUI)..."
    ufw allow 5678/tcp || true
    ufw allow 8080/tcp || true
  else
    warn "UFW is installed but not active. Skipping firewall changes."
  fi
else
  warn "UFW not installed; skipping firewall changes."
fi

### --- Bring up the stack ---
log "Pulling images and starting containers..."
cd "$STACK_DIR"
docker compose pull
docker compose up -d

log "Verifying containers are running..."
sleep 3
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'

# Basic health checks
N8N_OK=0
OWUI_OK=0
docker ps --format '{{.Names}} {{.Status}}' | grep -q '^n8n .*Up' && N8N_OK=1 || true
docker ps --format '{{.Names}} {{.Status}}' | grep -q '^open-webui .*Up' && OWUI_OK=1 || true

[ "$N8N_OK" -eq 1 ] || { err "n8n container is not running as expected."; exit 1; }
[ "$OWUI_OK" -eq 1 ] || { err "Open WebUI container is not running as expected."; exit 1; }

### --- Create updater script ---
UPDATER="/root/update_containers.sh"
log "Creating updater script: $UPDATER"
cat > "$UPDATER" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="/opt/stack"

echo "[+] Updating containers in $STACK_DIR ..."
cd "$STACK_DIR"

if ! command -v docker >/dev/null 2>&1; then
  echo "[!] Docker not found."
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo "[!] Docker Compose plugin not found."
  exit 1
fi

echo "[+] Pulling latest images..."
docker compose pull

echo "[+] Recreating with latest images..."
docker compose up -d

echo "[+] Cleanup old images..."
docker image prune -f

echo
read -rp "Do you want to reboot the server now? [y/N]: " REBOOT_ANS
case "${REBOOT_ANS:-N}" in
  y|Y) echo "[+] Rebooting..."; sleep 1; reboot ;;
  *) echo "[+] Skipping reboot." ;;
esac
EOS
chmod +x "$UPDATER"

### --- Final info ---
log "Installation complete."

cat <<INFO

============================================================
 n8n        : http://$SERVER_IP:5678
 Open WebUI : http://$SERVER_IP:8080
 Timezone   : $TZ_VAL
 Data dirs  :
   - n8n        -> $N8N_DATA_DIR
   - Open WebUI -> $OWUI_DATA_DIR
 Compose     : $STACK_DIR/docker-compose.yml
 Updater     : $UPDATER
============================================================

NOTE:
- We set N8N_SECURE_COOKIE=false so you can access n8n over plain HTTP immediately.
- When you enable HTTPS behind a reverse proxy:
    1) Edit $STACK_DIR/.env and set:
         N8N_SECURE_COOKIE=true
         N8N_PROTOCOL=https
         N8N_HOST=<your-n8n-domain>
         N8N_EDITOR_BASE_URL=https://<your-n8n-domain>
         WEBHOOK_URL=https://<your-n8n-domain>/
    2) (Optional) remove host port publish for n8n and let your proxy handle 443.
    3) Apply changes:
         cd $STACK_DIR && docker compose up -d

See the README reverse-proxy section for Caddy/Traefik examples.
INFO
