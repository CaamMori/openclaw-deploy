# Gotchas - OpenClaw Production Deployment

> Every entry from a real incident or real reproduction.

## 0. Silence is Not Confirmation
- No error != success
- Proof = observable evidence

## 1. AGENTS.md
- Hard cap ~20K chars, truncate from tail
- Index don delete
- Re-read after migration

## 2. Identity
- Two failures: can read? content exist?
- Must be in guaranteed injection layer

## 3. No Reply
- Check outbound send ok first
- Don probe api.telegram.org
- PATCH 204 != reloaded

## 4. Speed
- Duplicate rules = first wins
- DNS: rcode not getent
- idle watchdog 120s

## 5. TTFT
- 13% jump to 17-30s, physical
- Mitigate: streaming, timeout 40s

## 6. DNS Self-Loop
- mihomo DNS matches own proxy rules
- Fix: static hosts + extra_hosts
- API domains before GEOIP/CN

## 7. Cache/Perf
- Warmup 22 to 96 pct
- Cliff at 33K tokens
- Compaction deadlock at 99 pct

## 8. Security
- chmod 600 openclaw.json
- Hot-reload not kill -HUP
- uid 1000:1000 match
- No root gateway

## 9. Refactor
- cp -a first
- base64+md5 for relay

## 10. Rules (17)
1. Layer-test latency
2. Two-segment check
3. rcode not getent
4. Characteristic values
5. Self-validate tests
6. Trends not snapshots
7. Silence not confirmation
8. Fix A exposes B
9. Check specs first
10. Re-read output
11. cp -a
12. base64+md5
13. Stale lock 0-byte
14. Restart orphan netns
15. State limitations
16. Location not availability
17. Update stale memory
