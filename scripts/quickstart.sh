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
if ! command -v node &>/dev/null; then warn "Node.js not found. Installing via official binary..."; ARCH=$(uname -m); [ "$ARCH" = "x86_64" ] && ARCH="x64"; [ "$ARCH" = "aarch64" ] && ARCH="arm64"; NODE_VER="v20.18.1"; curl -fsSL "https://nodejs.org/dist/$NODE_VER/node-$NODE_VER-linux-$ARCH.tar.xz" | tar xJ -C /usr/local --strip-components=1; info "Node: $(node --version)"; fi
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
if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
  cp "$ENV_FILE" "$ENV_TARGET"; info "Copied from $ENV_FILE"
  warn "Pre-filled env: ensure providers are set, then run: openclaw models set <provider>/<model>"
else
echo ""; echo -e "${BOLD}Gateway / Telegram / misc (Enter to skip optional):${NC}"; echo ""
read -rp "  Gateway token (Enter to auto-generate): " INPUT_TOKEN
[ -z "$INPUT_TOKEN" ] && INPUT_TOKEN=$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
info "Token: ${INPUT_TOKEN:0:8}..."
read -rp "  Telegram bot token: " INPUT_TG_TOKEN
read -rp "  Telegram user ID (@userinfobot): " INPUT_TG_ID
read -rp "  GitHub token (optional): " INPUT_GH
read -rp "  Timezone [Asia/Shanghai]: " INPUT_TZ
INPUT_TZ="${INPUT_TZ:-Asia/Shanghai}"
cat > "$ENV_TARGET" <<ENVEOF
OPENCLAW_GATEWAY_TOKEN=$INPUT_TOKEN
TELEGRAM_BOT_TOKEN=$INPUT_TG_TOKEN
TELEGRAM_OWNER_ID=$INPUT_TG_ID
GH_TOKEN=$INPUT_GH
TZ=$INPUT_TZ
ENVEOF
chmod 600 "$ENV_TARGET"
info "runtime.env created (gateway-level secrets only)"
fi

# ---------------------------------------------------------------------------
# Model providers: generic loop.
#   - Built-in providers (openai/anthropic/zai/gemini/...) -> official env var
#     (gateway auto-reads them; no models.providers entry needed)
#   - custom / OpenAI- or Anthropic-compatible endpoint -> models.providers entry
#     in openclaw.json (baseUrl + apiKey + api type inferred from URL)
#   - primary model is set explicitly (replaces YOUR_PRIMARY_MODEL_HERE)
# Prefer `openclaw onboard --auth-choice custom-api-key` interactively if you
# want the wizard to auto-detect compatibility instead of editing files.
# ---------------------------------------------------------------------------
step "Configuring model providers..."
BUILTIN_ENV=()          # lines like "OPENAI_API_KEY=***"
PRIMARY_CANDIDATES=()   # lines like "openai/gpt-5.5"
PROV_JSON_DIR="$(mktemp -d)"
PCOUNT=0
# keyword -> "ENV_VAR|default_model"
declare -A B
B[openai]="OPENAI_API_KEY|gpt-5.5"
B[anthropic]="ANTHROPIC_API_KEY|claude-opus-4-6"
B[zai]="ZAI_API_KEY|glm-4.7"
B[gemini]="GEMINI_API_KEY|gemini-3-pro-preview"
B[deepseek]="DEEPSEEK_API_KEY|"
B[openrouter]="OPENROUTER_API_KEY|"
B[xai]="XAI_API_KEY|"
B[mistral]="MISTRAL_API_KEY|"
B[groq]="GROQ_API_KEY|"
B[minimax]="MINIMAX_API_KEY|"
B[moonshot]="MOONSHOT_API_KEY|"
echo "  Enter providers one per line. Type 'done' to finish."
echo "  built-in: openai anthropic zai gemini deepseek openrouter xai mistral groq minimax moonshot"
echo "  custom:   custom   (you'll be asked base URL + model id + key)"
while true; do
  read -rp "  Provider > " P
  [ -z "$P" ] && continue
  P="$(echo "$P" | tr '[:upper:]' '[:lower:]')"
  [ "$P" = "done" ] && break
  if [ "$P" = "custom" ]; then
    read -rp "    base URL (e.g. https://api.example.com/v1): " PURL
    read -rp "    model id (e.g. my-model): " PMID
    read -rp "    API key: " PKEY
    [ -z "$PURL" ] || [ -z "$PMID" ] || [ -z "$PKEY" ] && { warn "    custom needs baseUrl+modelId+key, skipped"; continue; }
    PNAME="custom$((++PCOUNT))"
    # infer api type from URL
    if echo "$PURL" | grep -qi 'anthropic'; then PTYPE="anthropic-messages"; else PTYPE="openai-completions"; fi
    cat > "$PROV_JSON_DIR/$PNAME.json" <<JSON
{
  "api": "$PTYPE",
  "baseUrl": "$PURL",
  "apiKey": "$PKEY",
  "models": [ { "id": "$PMID", "reasoning": false } ]
}
JSON
    info "    custom provider '$PNAME' ($PTYPE) added"
    PRIMARY_CANDIDATES+=("$PNAME/$PMID")
  elif [ -n "${B[$P]:-}" ]; then
    IFS='|' read -r EVAR DMODEL <<< "${B[$P]}"
    read -rp "    $EVAR: " PKEY
    [ -z "$PKEY" ] && { warn "    empty key, skipped"; continue; }
    BUILTIN_ENV+=("$EVAR=$PKEY")
    if [ -z "$DMODEL" ]; then
      read -rp "    model id (required for $P): " PMID
      [ -z "$PMID" ] && { warn "    no model id, skipped"; continue; }
    else
      read -rp "    model id [default: $DMODEL]: " PMID
      PMID="${PMID:-$DMODEL}"
    fi
    info "    $P -> $EVAR (model $PMID)"
    PRIMARY_CANDIDATES+=("$P/$PMID")
  else
    warn "    unknown '$P' (use a built-in name, 'custom', or 'done')"
  fi
done

# write built-in provider env vars into runtime.env
if [ ${#BUILTIN_ENV[@]} -gt 0 ]; then
  printf '\n# --- Model provider API keys (built-in; gateway auto-reads) ---\n' >> "$ENV_TARGET"
  for e in "${BUILTIN_ENV[@]}"; do echo "$e" >> "$ENV_TARGET"; done
  info "wrote ${#BUILTIN_ENV[@]} built-in provider key(s) to runtime.env"
fi

# choose primary model
OC_PRIMARY=""
if [ ${#PRIMARY_CANDIDATES[@]} -gt 0 ]; then
  echo ""; echo -e "${BOLD}Available primary candidates:${NC}"
  for i in "${!PRIMARY_CANDIDATES[@]}"; do echo "  $((i+1))) ${PRIMARY_CANDIDATES[$i]}"; done
  read -rp "  Primary model [default: 1]: " PCHOICE
  PCHOICE="${PCHOICE:-1}"
  if [[ "$PCHOICE" =~ ^[0-9]+$ ]] && [ "$PCHOICE" -ge 1 ] && [ "$PCHOICE" -le ${#PRIMARY_CANDIDATES[@]} ]; then
    OC_PRIMARY="${PRIMARY_CANDIDATES[$((PCHOICE-1))]}"
  else
    OC_PRIMARY="${PRIMARY_CANDIDATES[0]}"
  fi
  info "Primary model: $OC_PRIMARY"
else
  warn "No provider configured. After deploy run: openclaw models set <provider>/<model>"
fi

# patch openclaw.json: models.providers (custom) + agents.defaults.model.primary
step "Patching openclaw.json (providers + primary)..."
python3 - <<PYEOF
import json, glob, os
prov = {}
for f in glob.glob("$PROV_JSON_DIR/*.json"):
    name = os.path.splitext(os.path.basename(f))[0]
    prov[name] = json.load(open(f))
cfg = json.load(open("/data/state/openclaw.json"))
cfg.setdefault("models", {})["providers"] = prov
primary = os.environ.get("OC_PRIMARY", "")
if primary:
    cfg.setdefault("agents", {}).setdefault("defaults", {}).setdefault("model", {})["primary"] = primary
json.dump(cfg, open("/data/state/openclaw.json", "w"), indent=2, ensure_ascii=False)
print("  providers written:", list(prov.keys()) or "(none)")
print("  primary:", primary or "(unset)")
PYEOF
chmod 600 /data/state/openclaw.json
rm -rf "$PROV_JSON_DIR"

step "Customizing docker-compose..."
DC="/data/scripts/docker-compose.gateway.yml"
if [ -f "$DC" ]; then GID=$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo "999"); sed -i "s/YOUR_DOCKER_GROUP_ID/$GID/g" "$DC"; info "Docker GID: $GID"
VER=$(openclaw --version 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "latest"); sed -i "s/YOUR_OPENCLAW_VERSION_HERE/$VER/g" "$DC"; info "OpenClaw: $VER"
sed -i "s/YOUR_MIHOMO_VERSION_HERE/latest/g" "$DC"; info "mihomo: latest"; fi

step "Installing scripts..."
for s in selfcheck.py selfcheck-quick-cron.sh mihomo-guard.sh ensure-browser.sh ensure-telegram-alive.sh nightly-backup.sh pin-sbx-restart.sh entrypoint.sh; do [ -f "$SCRIPT_DIR/$s" ] && cp "$SCRIPT_DIR/$s" /usr/local/bin/ && chmod +x /usr/local/bin/$s && info "$s"; done

step "Initializing OpenClaw..."
if openclaw init 2>/tmp/oc-init.err; then
  info "Initialized"
elif grep -qi 'already initialized' /tmp/oc-init.err; then
  info "Already initialized"
else
  warn "openclaw init reported a problem:"; sed -n '1,20p' /tmp/oc-init.err 2>/dev/null
fi

step "Starting services..."
cd /data/scripts; docker compose -f docker-compose.gateway.yml up -d; info "Compose up done"

step "Waiting for Gateway health (max 60s)..."
for i in $(seq 1 20); do if openclaw health &>/dev/null; then info "Healthy after $((i*3))s"; break; fi; sleep 3; echo -n "."; done; echo ""
if ! openclaw health &>/dev/null; then warn "Gateway not healthy yet. Check: docker logs openclaw-gateway --tail 30"; fi

step "Running 22-item self-check..."
python3 /usr/local/bin/selfcheck.py --full 2>/dev/null || warn "selfcheck skipped"

echo ""; echo -e "${GREEN}${BOLD}============================================${NC}"; echo -e "${GREEN}${BOLD}  Deployment Complete!${NC}"; echo -e "${GREEN}${BOLD}============================================${NC}"; echo ""
docker ps --format '  {{.Names}} ({{.Status}})' 2>/dev/null | grep -E 'openclaw|mihomo' || true
echo ""; echo "  Quick commands:"; echo "    openclaw health"; echo "    openclaw doctor"; echo "    openclaw models list"; echo "    python3 /usr/local/bin/selfcheck.py --full"; echo ""
echo -e "${BOLD}  Recommended cron entries (add to /etc/crontab or crontab -e):${NC}"
echo "    */10 * * * * root python3 /usr/local/bin/selfcheck.py --full --json >> /var/log/selfcheck.log 2>&1"
echo "    */5  * * * * root /usr/local/bin/mihomo-guard.sh"
echo "    */10 * * * * root /usr/local/bin/ensure-browser.sh"
echo "    */5  * * * * root /usr/local/bin/ensure-telegram-alive.sh"
echo "    0    4 * * * root /usr/local/bin/nightly-backup.sh"
echo ""
