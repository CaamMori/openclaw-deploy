#!/usr/bin/env bash
# OpenClaw One-Click Deployment
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[X]${NC} $*" >&2; }
step()  { echo -e "\n${CYAN}${BOLD}==> $*${NC}"; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates"
ENV_FILE="${1:-}"

step "Checking prerequisites..."
if ! command -v docker &>/dev/null; then error "Docker not found. https://docs.docker.com/engine/install/"; exit 1; fi
info "Docker: $(docker --version | head -1)"
if ! docker compose version &>/dev/null; then error "Docker Compose v2 not found."; exit 1; fi
info "Compose: $(docker compose version --short)"
if ! command -v node &>/dev/null; then warn "Node.js not found. Installing..."; curl -fsSL https://deb.nodesource.com/setup_20.x | bash -; apt-get install -y nodejs; fi
info "Node: $(node --version)"

step "Checking OpenClaw CLI..."
if command -v openclaw &>/dev/null; then info "Already installed: $(openclaw --version 2>/dev/null || echo unknown)"; else info "Installing..."; npm install -g openclaw; info "Installed: $(openclaw --version 2>/dev/null || echo done)"; fi

step "Creating /data structure..."
mkdir -p /data/{state/workspace,scripts,etc/openclaw,etc/mihomo,opt,backups}
info "Done"

step "Copying templates..."
[ -f "$TEMPLATE_DIR/docker-compose.gateway.yml" ] && cp "$TEMPLATE_DIR/docker-compose.gateway.yml" /data/scripts/ && info "docker-compose"
[ -f "$TEMPLATE_DIR/openclaw.json" ] && cp "$TEMPLATE_DIR/openclaw.json" /data/state/ && chmod 600 /data/state/openclaw.json && info "openclaw.json"
[ -f "$TEMPLATE_DIR/mihomo-config.yaml" ] && cp "$TEMPLATE_DIR/mihomo-config.yaml" /data/etc/mihomo/config.yaml && info "mihomo-config"

step "Configuring environment..."
ENV_TARGET="/data/etc/openclaw/runtime.env"
[ -f "$ENV_TARGET" ] && cp "$ENV_TARGET" "${ENV_TARGET}.bak.$(date +%s)" && warn "Backed up existing"
if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then cp "$ENV_FILE" "$ENV_TARGET"; info "Copied from $ENV_FILE"; else
echo ""; echo -e "${BOLD}Enter your keys (Enter to skip optional):${NC}"; echo ""
read -rp "  Gateway token (Enter to auto-generate): " INPUT_TOKEN
[ -z "$INPUT_TOKEN" ] && INPUT_TOKEN=$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
info "Token: ${INPUT_TOKEN:0:8}..."
read -rp "  ZAI API key: " INPUT_ZAI
read -rp "  OpenAI API key (optional): " INPUT_OPENAI
read -rp "  Telegram bot token: " INPUT_TG_TOKEN
read -rp "  Telegram user ID (@userinfobot): " INPUT_TG_ID
read -rp "  GitHub token (optional): " INPUT_GH
read -rp "  Timezone [Asia/Shanghai]: " INPUT_TZ
INPUT_TZ="${INPUT_TZ:-Asia/Shanghai}"
cat > "$ENV_TARGET" <<ENVEOF
OPENCLAW_GATEWAY_TOKEN=$INPUT_TOKEN
ZAI_API_KEY=$INPUT_ZAI
OPENAI_API_KEY=$INPUT_OPENAI
TELEGRAM_BOT_TOKEN=$INPUT_TG_TOKEN
TELEGRAM_OWNER_ID=$INPUT_TG_ID
GH_TOKEN=$INPUT_GH
TZ=$INPUT_TZ
ENVEOF
info "runtime.env created"; fi
chmod 600 "$ENV_TARGET"

step "Customizing docker-compose..."
DC="/data/scripts/docker-compose.gateway.yml"
if [ -f "$DC" ]; then GID=$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo "999"); sed -i "s/YOUR_DOCKER_GROUP_ID/$GID/g" "$DC"; info "Docker GID: $GID"
VER=$(openclaw --version 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "latest"); sed -i "s/YOUR_OPENCLAW_VERSION_HERE/$VER/g" "$DC"; info "OpenClaw: $VER"
sed -i "s/YOUR_MIHOMO_VERSION_HERE/latest/g" "$DC"; info "mihomo: latest"; fi

step "Installing scripts..."
for s in selfcheck.py mihomo-guard.sh ensure-browser.sh entrypoint.sh; do [ -f "$SCRIPT_DIR/$s" ] && cp "$SCRIPT_DIR/$s" /usr/local/bin/ && chmod +x /usr/local/bin/$s && info "$s"; done

step "Initializing OpenClaw..."
openclaw init 2>/dev/null || info "Already initialized"

step "Starting services..."
cd /data/scripts; docker compose -f docker-compose.gateway.yml up -d; info "Compose up done"

step "Waiting for Gateway health (max 60s)..."
for i in $(seq 1 20); do if openclaw health &>/dev/null; then info "Healthy after $((i*3))s"; break; fi; sleep 3; echo -n "."; done; echo ""
if ! openclaw health &>/dev/null; then warn "Gateway not healthy yet. Check: docker logs openclaw-gateway --tail 30"; fi

step "Running 22-item self-check..."
python3 /usr/local/bin/selfcheck.py --full 2>/dev/null || warn "selfcheck skipped"

echo ""; echo -e "${GREEN}${BOLD}============================================${NC}"; echo -e "${GREEN}${BOLD}  Deployment Complete!${NC}"; echo -e "${GREEN}${BOLD}============================================${NC}"; echo ""
docker ps --format '  {{.Names}} ({{.Status}})' 2>/dev/null | grep -E 'openclaw|mihomo' || true
echo ""; echo "  Quick commands:"; echo "    openclaw health"; echo "    openclaw doctor"; echo "    python3 /usr/local/bin/selfcheck.py --full"; echo ""
