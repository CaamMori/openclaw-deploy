#!/usr/bin/env bash
# ============================================================
# OpenClaw Production Deployment - Quickstart
# ============================================================
# Usage:
#   curl -sL https://raw.githubusercontent.com/CaamMori/openclaw-deploy/main/scripts/quickstart.sh | bash
#   OR: git clone https://github.com/CaamMori/openclaw-deploy.git && cd openclaw-deploy && bash scripts/quickstart.sh
#
# This script:
#   1. Creates /data directory structure
#   2. Copies templates with YOUR_ placeholders
#   3. Generates a secure gateway token
#   4. Prints next steps
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[X]${NC} $*" >&2; }

# Check prerequisites
if ! command -v docker &>/dev/null; then
    error "Docker not found. Install: https://docs.docker.com/engine/install/"
    exit 1
fi

if ! docker compose version &>/dev/null; then
    error "Docker Compose v2 not found. Update Docker to latest."
    exit 1
fi

# Create directory structure
info "Creating /data directory structure..."
mkdir -p /data/{state/workspace,scripts,etc/openclaw,opt,backups}

# Copy templates
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates"

if [ -d "$TEMPLATE_DIR" ]; then
    info "Copying templates..."
    cp "$TEMPLATE_DIR/docker-compose.gateway.yml" /data/scripts/
    cp "$TEMPLATE_DIR/openclaw.json" /data/state/
    cp "$TEMPLATE_DIR/mihomo-config.yaml" /data/etc/mihomo/config.yaml 2>/dev/null || true
    chmod 600 /data/state/openclaw.json
else
    warn "Templates directory not found. Using defaults."
fi

# Generate gateway token
TOKEN=$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 64)
info "Generated gateway token: ${TOKEN:0:8}..."

# Create runtime.env from template
ENV_FILE="/data/etc/openclaw/runtime.env"
if [ ! -f "$ENV_FILE" ]; then
    cat > "$ENV_FILE" <<ENVEOF
# OpenClaw Runtime Environment
# chmod 600 this file after editing.

OPENCLAW_GATEWAY_TOKEN=$TOKEN
ZAI_API_KEY=YOUR_ZAI_API_KEY_HERE
OPENAI_API_KEY=YOUR_OPENAI_API_KEY_HERE
TELEGRAM_BOT_TOKEN=YOUR_TELEGRAM_BOT_TOKEN_HERE
TELEGRAM_OWNER_ID=YOUR_TELEGRAM_USER_ID_HERE
TZ=Asia/Shanghai
ENVEOF
    chmod 600 "$ENV_FILE"
    info "Created $ENV_FILE"
else
    warn "$ENV_FILE already exists, skipping."
fi

# Validate docker-compose
if [ -f /data/scripts/docker-compose.gateway.yml ]; then
    if cd /data/scripts && docker compose -f docker-compose.gateway.yml config --quiet 2>/dev/null; then
        info "docker-compose.yml syntax OK"
    else
        warn "docker-compose.yml has syntax errors or missing values. Edit and retry."
    fi
    cd - >/dev/null
fi

echo ""
echo "============================================"
echo "  Quickstart Complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Edit /data/etc/openclaw/runtime.env"
echo "     - Fill in YOUR_ placeholders (API keys, bot token, user ID)"
echo ""
echo "  2. Edit /data/scripts/docker-compose.gateway.yml"
echo "     - Change YOUR_DOCKER_GROUP_ID"
echo "       Run: stat -c '%g' /var/run/docker.sock"
echo "     - Change YOUR_OPENCLAW_VERSION_HERE"
echo ""
echo "  3. Start services:"
echo "     cd /data/scripts && docker compose -f docker-compose.gateway.yml up -d"
echo ""
echo "  4. Verify:"
echo "     openclaw health"
echo "     openclaw doctor"
echo ""
echo "  5. Run self-check:"
echo "     python3 $SCRIPT_DIR/selfcheck.py --full"
echo ""
info "Done. Edit the YOUR_ placeholders and start!"
