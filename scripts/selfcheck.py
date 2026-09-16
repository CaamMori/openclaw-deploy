#!/usr/bin/env python3
import json,os,subprocess,sys
from pathlib import Path
W=Path("/data/state/workspace")
def run(c,t=10):
 try:r=subprocess.run(c,shell=True,capture_output=True,text=True,timeout=t);return r.returncode,r.stdout.strip()
 except:return-1,"timeout"
def ck(n,f):
 try:o,d=f()
 except Exception as e:o,d=False,str(e)
 return{n:n,"ok":o,"detail":d}
def gw():c,o=run("openclaw health");return c==0,o
def ch():c,o=run("docker exec openclaw-gateway which chromium");return c==0,o
def mh():c,o=run("docker exec openclaw-gateway ip addr show tun0");return c==0 and "tun0" in o,o
def dn():c,o=run("docker exec openclaw-gateway getent hosts api.telegram.org");return c==0 and o!="" o
def dk():c,o=run("df / --output=pcent | tail -1");
 if c!=0:return False,o
 pct=int(o.strip().rstrip("%"));return pct<80,str(pct)+"%"
def mm():c,o=run("free -m | awk /Mem:/{print $3/$2*100}");return float(o)<90 if c==0 else (False,o)
def pd():c,o=run("docker stats --no-stream --format {{.PIDs}} openclaw-gateway");
 if c!=0:return False,o
 try:return int(o)<800,o
 except:return False,"parse: "+o
def zb():c,o=run("docker exec openclaw-gateway ps -eo stat --no-headers | grep -c Z");
 if c!=0:return False,o
 try:return int(o)<50,o
 except:return False,"parse: "+o
def cf():c,o=run("openclaw config validate");return c==0,o
def wk():c,o=run("ls /workspace/AGENTS.md");return c==0,o
def lk():locks=list(W.glob("*lock.sqlite*"));stale=[f for f in locks if f.stat().st_size==0];return len(stale)==0,str(len(stale))+" stale"
def ix():c,o=run("openclaw memory status 2>&1 | grep -c stale");return c==0 and o=="0",o
CHECKS=[("gateway",gw),("chromium",ch),("mihomo",mh),("dns",dn),("disk",dk),("memory",mm),("pids",pd),("zombies",zb),("config",cf),("workspace",wk),("locks",lk),("index",ix)]
def main():
 full="--full" in sys.argv
 results=[ck(n,f) for n,f in CHECKS]
 passed=sum(1 for r in results if r["ok"])
 for r in results:
  icon="+" if r["ok"] else "X"
  if full or not r["ok"]:print("  [%s] %s: %s"%(icon,r["name"],r["detail"]))
 print("%d/%d passed"%(passed,len(results)))
 sys.exit(0 if passed==len(results) else 1)
if __name__=="__main__":main()
