# Architecture - OpenClaw Production Deployment

## Topology

```
Host Server (Linux x86_64, 4C/4G/80G)
|
+-- docker compose (/data/scripts/docker-compose.gateway.yml)
|   +-- openclaw-gateway        Main process (session orchestration, model dispatch)
|   |   +-- Config: /data/state/openclaw.json (hot-reload)
|   |   +-- Workspace: /data/state/workspace/ (bind mount, always fresh)
|   |   +-- Memory: managed llama.cpp local embedding (on-demand)
|   |   +-- Browser: Chromium (on-demand)
|   |
|   +-- mihomo-tun              Proxy sidecar (TUN 198.18.0.0/15)
|   |   +-- network_mode: service:gateway (shared netns)
|   |   +-- Control API: 127.0.0.1:9090 (only reachable in gateway netns)
|   |
|   +-- openclaw-recovery-watchdog  Crash recovery (15s heartbeat)
|   |
|   +-- Sandbox containers (auto-rebuilt by configHash)
|       +-- openclaw-sbx-workspace-<hash>       exec/read/write
|       +-- openclaw-sbx-browser-workspace-<hash>  isolated network
|
+-- Host cron (10 watchdog scripts)
+-- systemd: ocwatch / recovery-watchdog / te-daemon
+-- /usr/local/bin/*.sh         Ops scripts
```

## Data Flow

1. User message -> Telegram Bot API -> OpenClaw Gateway
2. Gateway dispatches to sandbox container -> agent processes
3. Agent calls model -> mihomo TUN -> proxy node -> model API
4. Agent calls tools -> exec/read/write in sandbox
5. Reply -> Gateway -> Telegram Bot API -> User

## Key Design Decisions

### Why TUN instead of HTTP proxy
- TUN captures all egress automatically, agent code needs no proxy config
- Trade-off: DNS needs extra handling (fake-ip / DNS hijack)

### Why bind mount workspace (not snapshot)
- Old architecture used one-shot snapshots -> stale files (8-day-old AGENTS.md)
- Bind mount guarantees always-fresh content
- Trade-off: uid management critical (gateway vs sandbox must match)

### Why hot-reload instead of restart
- Restart = container ID changes -> mihomo netns breaks -> all egress dies
- Restart = all sandbox containers rebuilt -> sessions interrupted
- Hot-reload = zero downtime, wait for "config hot reload applied" in logs

## Container Roles

| Container | Purpose | Network |
|---|---|---|
| openclaw-gateway | Main process | host (shared netns) |
| mihomo-tun | Proxy sidecar | service:gateway |
| openclaw-recovery-watchdog | Crash recovery | host |
| openclaw-sbx-workspace-* | exec sandbox | container:gateway |
| openclaw-sbx-browser-workspace-* | browser sandbox | isolated |

## Why Gateway Uses Host Network

- TUN device needs NET_ADMIN + /dev/net/tun
- Host networking shares host netns, mihomo TUN captures all egress
- Trade-off: ports exposed directly, must protect with auth.token + rateLimit
