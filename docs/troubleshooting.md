# Troubleshooting Guide

## Quick Diagnosis

```bash
openclaw health
python3 /usr/local/bin/selfcheck.py --full
cat /data/state/workspace/memory/ENV-SNAPSHOT.md
docker logs openclaw-gateway --tail 50
curl http://127.0.0.1:9090/proxies/main-proxy
```

## Common Failures

### Agent doesn't reply

Two-segment check (see gotchas.md section 3):

```
Model returns 200? --> Any "outbound send ok" in logs?
  YES                YES -> Telegram issue (check Bot Token)
  YES                NO  -> Delivery broken (check egress/proxy)
  NO                 --  -> Model API issue (check provider status)
```

Commands:
```bash
docker exec openclaw-gateway curl -s -o /dev/null -w "%{http_code}" https://api.openai.com/v1/models
docker exec openclaw-gateway curl -s -o /dev/null -w "%{http_code}" https://api.telegram.org
docker logs openclaw-gateway 2>&1 | grep -i "error" | tail -20
```

### Slow responses

1. Check TTFT: send a simple message, time the first token
2. Check proxy latency: curl -w "%{time_connect}" -o /dev/null -s https://api.openai.com
3. Check context size: large contexts = slow model calls

Fixes:
- Enable streaming: streaming.mode: "partial"
- Lower idle watchdog: timeoutSeconds: 40
- Prune old sessions

### Sandbox write fails (PermissionError)

Root cause: uid mismatch between gateway and sandbox.

```bash
docker exec openclaw-gateway id   # should be uid=1000(node)
ls -la /data/state/workspace/     # should be owned by 1000:1000
chown -R 1000:1000 /data/state/workspace
```

### mihomo netns broken after gateway restart

```bash
docker compose -f docker-compose.gateway.yml up -d --force-recreate mihomo-tun
docker restart $(docker ps -q --filter "name=openclaw-sbx")
docker exec openclaw-gateway ip addr show tun0
```

### Zombie processes -> pids exhausted -> EAGAIN

```bash
docker stats --format '{{.PIDs}}' openclaw-gateway  # if > 800, danger
docker exec openclaw-gateway ps -eo stat --no-headers | grep -c Z  # if > 50, zombies
```

Fix: stop the exec loop, set pids: -1 in compose, rebuild container.

## Gotchas Reference

See docs/gotchas.md for detailed explanations:
- Section 3: No reply diagnosis
- Section 4: Response speed
- Section 5: TTFT instability
- Section 6: DNS self-loop
- Section 7: Performance and caching
- Section 8: Security and credentials
