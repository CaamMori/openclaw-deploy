#!/usr/bin/env python3
"""OpenClaw self-check - 22-item production health check.

Usage:
  python3 selfcheck.py           # quick check (only shows failures)
  python3 selfcheck.py --full    # full check (always output everything)
  python3 selfcheck.py --json    # JSON output for automation

Exit codes: 0 = all passed, 1 = one or more failed
"""
import json, os, re, subprocess, sys, time
from pathlib import Path

WORKSPACE = Path("/data/state/workspace")
STATE_DIR = Path("/data/state")
OPENCLAW_JSON = STATE_DIR / "openclaw.json"
RUNTIME_ENV = Path("/data/etc/openclaw/runtime.env")
BACKUP_DIR = Path("/data/backups")
GW = "openclaw-gateway"

def run(cmd, timeout=10):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip()
    except subprocess.TimeoutExpired:
        return -1, "timeout"
    except Exception as e:
        return -1, str(e)

def file_age(path):
    try: return time.time() - path.stat().st_mtime
    except: return -1

# === 22 Checks ===

def check_gateway_health():
    """1. Gateway process is healthy."""
    code, out = run("openclaw health", timeout=15)
    return code == 0, out

def check_chromium():
    """2. Chromium binary available."""
    code, out = run("docker exec " + GW + " which chromium")
    if code != 0: return False, "not found"
    code2, out2 = run("docker exec " + GW + " ldd /usr/lib/chromium/chromium 2>&1 | grep -c 'not found'")
    if code2 == 0 and out2 != "0": return False, out2 + " missing libs"
    return True, "ok"

def check_mihomo_tun():
    """3. mihomo TUN interface up."""
    code, out = run("docker exec " + GW + " ip addr show tun0")
    return (code == 0 and "tun0" in out), ("up" if code == 0 else "not found")

def check_dns():
    """4. DNS resolution works."""
    code, out = run("docker exec " + GW + " getent hosts api.telegram.org")
    return (code == 0 and out != ""), (out.split()[0] if out else "failed")

def check_disk():
    """5. Disk below 80%."""
    code, out = run("df / --output=pcent | tail -1")
    if code != 0: return False, "df failed"
    try: pct = int(out.strip().rstrip("%"))
    except: return False, "parse error"
    return pct < 80, str(pct) + "%"

def check_memory():
    """6. Memory below 90%."""
    code, out = run("free -m | awk '/Mem:/{print $3/$2*100}'")
    if code != 0: return False, "free failed"
    try: return float(out) < 90, out
    except: return False, "parse error"

def check_pids():
    """7. PIDs headroom."""
    code, out = run("docker stats --no-stream --format '{{.PIDs}}' " + GW)
    if code != 0: return False, "stats failed"
    try: pids = int(out)
    except: return False, "parse: " + out
    return pids < 800, str(pids) + " (" + ("CRITICAL" if pids >= 800 else "WARN" if pids >= 600 else "ok") + ")"

def check_zombies():
    """8. Zombie count."""
    code, out = run("docker exec " + GW + " ps -eo stat --no-headers | grep -c Z")
    if code != 0: return False, "ps failed"
    try: z = int(out)
    except: return False, "parse: " + out
    return z < 50, str(z) + " (" + ("CRITICAL" if z >= 50 else "WARN" if z >= 10 else "ok") + ")"

def check_config_valid():
    """9. openclaw.json valid."""
    if not OPENCLAW_JSON.exists(): return False, "not found"
    try:
        with open(OPENCLAW_JSON) as f: c = json.load(f)
    except json.JSONDecodeError as e: return False, "invalid JSON"
    missing = [k for k in ["gateway", "channels", "agents", "models"] if k not in c]
    if missing: return False, "missing: " + ", ".join(missing)
    return True, "valid"

def check_config_permissions():
    """10. openclaw.json perms 600."""
    if not OPENCLAW_JSON.exists(): return False, "not found"
    mode = oct(OPENCLAW_JSON.stat().st_mode)[-3:]
    return mode == "600", mode

def check_workspace_bind():
    """11. Workspace bind-mounted."""
    code, _ = run("ls /workspace/AGENTS.md")
    return code == 0, "ok" if code == 0 else "AGENTS.md missing"

def check_workspace_uid():
    """12. Workspace uid 1000."""
    code, out = run("stat -c '%u' /workspace/AGENTS.md 2>/dev/null")
    if code != 0: code, out = run("stat -c '%u' /data/state/workspace/AGENTS.md 2>/dev/null")
    if code != 0: return False, "cannot determine"
    return out.strip() == "1000", "uid=" + out.strip()

def check_stale_lock():
    """13. No stale reindex locks."""
    if not WORKSPACE.exists(): return False, "workspace not found"
    locks = list(WORKSPACE.glob("*lock.sqlite*"))
    stale = [f for f in locks if f.stat().st_size == 0 and file_age(f) > 1800]
    return len(stale) == 0, str(len(stale)) + " stale" if stale else str(len(locks)) + " active"

def check_memory_index():
    """14. Memory index complete."""
    code, out = run("openclaw memory status 2>&1")
    if code != 0: return False, "failed"
    if "stale" in out.lower(): return False, "stale entries"
    return True, "clean"

def check_runtime_env():
    """15. runtime.env exists, perms 600."""
    if not RUNTIME_ENV.exists(): return False, "not found"
    size = RUNTIME_ENV.stat().st_size
    if size == 0: return False, "empty"
    mode = oct(RUNTIME_ENV.stat().st_mode)[-3:]
    return mode == "600", str(size) + " bytes, perm=" + mode

def check_docker_socket():
    """16. Docker socket accessible."""
    code, out = run("docker exec " + GW + " docker ps --format '{{.Names}}' | head -1")
    return (code != -1 and out != ""), "ok" if out else "failed"

def check_mihomo_running():
    """17. mihomo container running."""
    code, out = run("docker ps --format '{{.Names}}' | grep mihomo")
    return (code == 0 and "mihomo" in out), "running" if "mihomo" in out else "not running"

def check_browser_bundle():
    """18. Chromium recovery bundle exists."""
    b = Path("/usr/local/lib/openclaw-browser/bundle-full.tar.gz")
    if b.exists(): return True, "{:.0f}MB".format(b.stat().st_size / 1024 / 1024)
    code, out = run("find / -name 'bundle-full.tar.gz' -maxdepth 4 2>/dev/null | head -1")
    return (code == 0 and bool(out)), "found" if out else "not found"

def check_gateway_logs():
    """19. No recent crashes."""
    code, out = run("docker logs " + GW + " --since 1h 2>&1 | grep -ci 'crash\\|panic\\|fatal'")
    if code != 0: return False, "cannot read"
    try: count = int(out)
    except: count = 0
    return count == 0, str(count) + " issues" if count > 0 else "clean"

def check_nightly_backup():
    """20. Backup within 48h."""
    if not BACKUP_DIR.exists(): return False, "no backup dir"
    backups = sorted(BACKUP_DIR.glob("nightly-*"), reverse=True)
    if not backups: return False, "no backups"
    age = file_age(backups[0])
    if age < 0: return False, "stat failed"
    hours = age / 3600
    return hours < 48, "{:.0f}h ago".format(hours)

def check_skill_bins():
    """21. Skill binaries available."""
    missing = [b for b in ["gh", "tmux"] if run("which " + b)[0] != 0]
    return len(missing) == 0, "ok" if not missing else "missing: " + ", ".join(missing)

def check_version():
    """22. OpenClaw version."""
    code, out = run("openclaw --version 2>/dev/null || openclaw version 2>/dev/null")
    return (code == 0), out if code == 0 else "unknown"

# === Runner ===

CHECKS = [
    ("gateway_health", check_gateway_health), ("chromium", check_chromium),
    ("mihomo_tun", check_mihomo_tun), ("dns", check_dns),
    ("disk", check_disk), ("memory", check_memory),
    ("pids", check_pids), ("zombies", check_zombies),
    ("config_valid", check_config_valid), ("config_perms", check_config_permissions),
    ("workspace_bind", check_workspace_bind), ("workspace_uid", check_workspace_uid),
    ("stale_lock", check_stale_lock), ("memory_index", check_memory_index),
    ("runtime_env", check_runtime_env), ("docker_socket", check_docker_socket),
    ("mihomo_running", check_mihomo_running), ("browser_bundle", check_browser_bundle),
    ("gateway_logs", check_gateway_logs), ("backup", check_nightly_backup),
    ("skill_bins", check_skill_bins), ("version", check_version),
]

def main():
    full = "--full" in sys.argv
    as_json = "--json" in sys.argv
    results = []
    for name, fn in CHECKS:
        try: ok, detail = fn()
        except Exception as e: ok, detail = False, str(e)
        results.append({"name": name, "ok": ok, "detail": detail})
    passed = sum(1 for r in results if r["ok"])
    failed = len(results) - passed
    if as_json:
        print(json.dumps({"passed": passed, "failed": failed, "total": len(results), "results": results}, indent=2))
    else:
        for r in results:
            icon = "+" if r["ok"] else "X"
            if full or not r["ok"]:
                print("  [%s] %s: %s" % (icon, r["name"], r["detail"]))
        sym = "+" if failed == 0 else "X"
        print("\n%s %d/%d passed" % (sym, passed, len(results)))
    sys.exit(0 if failed == 0 else 1)

if __name__ == "__main__":
    main()
