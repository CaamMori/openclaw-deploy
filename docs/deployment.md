# Deployment Guide - From Zero to Running

## Prerequisites

- Linux server (x86_64, 4C/4G/80G minimum)
- Docker + Docker Compose v2
- Node.js 20+
- Working proxy subscription (VLESS/Trojan/etc)
- Telegram Bot Token (create via @BotFather)

## Step 1: Install OpenClaw

```bash
npm install -g openclaw
openclaw init
```

## Step 2: Create Directory Structure

```bash
mkdir -p /data/{state,scripts,etc/openclaw,opt}
mkdir -p /data/state/workspace/{memory,handoff,runbooks}
```

## Step 3: Configure Gateway

```bash
cp templates/openclaw.json /data/state/openclaw.json
chmod 600 /data/state/openclaw.json
```

Edit and fill in:
- gateway.auth.token - generate: python3 -c "import secrets; print(secrets.token_urlsafe(32))"
- channels.telegram.token - your Bot Token from @BotFather
- channels.telegram.allowFrom - your Telegram User ID
- commands.ownerAllowFrom - same as above
- models.providers.* - your API provider config

## Step 4: Configure Proxy (mihomo)

```bash
cp templates/mihomo-config.yaml /usr/local/etc/mihomo/config.yaml
```

Replace with your proxy nodes. See gotchas.md section 6 for DNS self-loop warnings.

Critical: API domains (telegram.org, openai.com, etc.) MUST have explicit proxy rules BEFORE any GEOIP/CN rules.

## Step 5: Environment Variables

```bash
cp templates/runtime.env.example /data/etc/openclaw/runtime.env
chmod 600 /data/etc/openclaw/runtime.env
```

Fill in your API keys and tokens.

## Step 6: Start

```bash
cd /data/scripts
docker compose -f docker-compose.gateway.yml up -d
```

## Step 7: Verify

```bash
openclaw health
openclaw doctor
docker logs -f openclaw-gateway
```

## Step 8: Test Telegram

Send a message to your bot. If no reply:
1. Check docker logs for "outbound send ok"
2. No send record = generation problem (check model API)
3. Send record exists = delivery problem (check Telegram Bot Token)
