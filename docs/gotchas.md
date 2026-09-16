# Gotchas - OpenClaw Production Deployment

> Every entry from a real incident or real reproduction.

## 0. Silence is Not Confirmation
- No error != success
- Valid proof = observable evidence: "Memory index updated", "config hot reload applied", "outbound send ok"

## 1. AGENTS.md Information Architecture
- Hard cap ~20K chars, truncates from tail (loses ops core rules)
- Index, don't delete: AGENTS.md = identity + invariants + doc index
- After migration: re-read line by line. Title exists != content exists
- HEARTBEAT.md / TOOLS.md are RETIRED in official docs

## 2. Identity and Injection
- Two failures: can it read? does content exist?
- Identity in guaranteed injection layer (AGENTS.md header)
- Permission grant != identity visibility

## 3. No Reply Two-Segment Check
- Model 200 + no "outbound send ok" = delivery broke
- Don't probe api.telegram.org (false positives); use gstatic/generate_204
- PATCH 204 != config reloaded; check GET /proxies
- Dead node takes 5min to switch (interval=300)

## 4. Response Speed
1. Duplicate rules = first wins (traffic to dead node)
2. DNS SERVFAIL: send DNS query, check rcode
3. idle watchdog 120s

## 5. TTFT Unstable
- 13% jump to 17-30s (worst 133.9s)
- Cross-border 10% failure rate - physical
- Mitigate: streaming partial, timeoutSeconds 40

## 6. DNS Self-Loop Deadlock
- mihomo DNS matches own proxy rules -> deadlock
- Fix: static /etc/hosts + extra_hosts
- API domains BEFORE GEOIP/CN

## 7. Cache and Performance
- Warmup 22% -> 96%
- Cliff at 33K tokens
- Compaction deadlock at 99%
- Compaction model separate, lightweight

### 7.1 Compaction Deadlock
- Session 99% -> all messages blocked
- Default reuses session model (too slow)
- Use large contextWindow models

## 8. Security
- chmod 600 openclaw.json
- ${ENV} != audit-clean
- Hot-reload, not kill -HUP
- uid 1000:1000 match
- No root gateway

## 9. Refactoring
- cp -a first
- base64+md5 for relay
- Ask before destructive

## 10. Rules (17)
1. Layer-test latency
2. Two-segment check
3. rcode not getent
4. Characteristic values
5. Self-validate tests
6. Trends not snapshots
7. Silence != confirmation
8. Fix A exposes B
9. Check specs
10. Re-read output
11. cp -a
12. base64+md5
13. Stale lock 0-byte
14. Restart -> orphan netns
15. State limitations
16. Location != availability
17. Update stale memory
