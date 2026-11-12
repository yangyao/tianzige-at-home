#!/bin/sh
# 端到端演示：启动服务（mock OCR）→ 上传一张图 → 轮询到 done → 读 /api/day → 取回原图。
# 用法：sh scripts/demo.sh    （在仓库任意位置执行均可）
set -eu

cd "$(dirname "$0")/.."
ADDR="${ADDR:-127.0.0.1:18080}"
BASE="http://$ADDR"
WORK="$(mktemp -d)"
DATA="$WORK/data"
PID=""

cleanup() {
  if [ -n "$PID" ]; then kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

echo "== 编译 =="
go build -o "$WORK/homework-server" ./cmd/server

echo "== 启动（mock OCR + 行分科）=="
TIANZIGE_OCR=mock TIANZIGE_LLM=lines \
  "$WORK/homework-server" -addr "$ADDR" -data "$DATA" >"$WORK/server.log" 2>&1 &
PID=$!

i=0
while [ $i -lt 50 ]; do
  if curl -fsS "$BASE/api/health" >/dev/null 2>&1; then break; fi
  i=$((i + 1))
  sleep 0.2
done
HEALTH="$(curl -fsS "$BASE/api/health")"
echo "health: $HEALTH"

# 80x40 的 PNG，内嵌避免依赖 ImageMagick
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAFAAAAAoCAIAAADmAupWAAAAUUlEQVR4nOzPAQ2AMADEwE9Y8C8LWfjo7lIDPdv3bPd09u4qhusM1xmuM1xnuM5wneE6w3WG6wzXGa4zXGe4znCd4TrDdYbrDNcZrvsDAAD//0RKA0Ah20zcAAAAAElFTkSuQmCC' \
  | base64 -d >"$WORK/homework.png"

# 用服务端返回的时间取日期，避免本机时区与 Asia/Shanghai 不一致
DATE="$(printf '%s' "$HEALTH" | sed -n 's/.*"time":"\([0-9][0-9-]*\)T.*/\1/p')"
[ -n "$DATE" ] || DATE="$(date +%Y-%m-%d)"
echo "== POST /api/ingest（日期 $DATE）=="
INGEST="$(curl -fsS -X POST "$BASE/api/ingest" \
  -F "files=@$WORK/homework.png;type=image/png" \
  -F "note=数学练习册 P18" \
  -F "date=$DATE")"
echo "$INGEST"

BATCH_ID="$(printf '%s' "$INGEST" | sed -n 's/.*"batch_id":\([0-9][0-9]*\).*/\1/p')"
if [ -z "$BATCH_ID" ]; then echo "没拿到 batch_id" >&2; exit 1; fi

echo "== 轮询 /api/batch/$BATCH_ID =="
i=0
while [ $i -lt 100 ]; do
  BATCH="$(curl -fsS "$BASE/api/batch/$BATCH_ID")"
  STATUS="$(printf '%s' "$BATCH" | sed -n 's/.*"status":"\([a-z]*\)".*/\1/p')"
  echo "  status=$STATUS"
  if [ "$STATUS" = "done" ]; then break; fi
  if [ "$STATUS" = "failed" ]; then echo "$BATCH"; exit 1; fi
  i=$((i + 1))
  sleep 0.2
done

echo "== GET /api/day?date=$DATE =="
DAY="$(curl -fsS "$BASE/api/day?date=$DATE")"
echo "$DAY" | head -c 600; echo
echo "$DAY" | grep -q '"state":"ready"' || { echo "state 不是 ready" >&2; exit 1; }

IMG_URL="$(printf '%s' "$DAY" | sed -n 's|.*"url":"\(/img/[^"]*\)".*|\1|p' | head -n 1)"
echo "== GET $IMG_URL =="
curl -fsS "$BASE$IMG_URL" -o "$WORK/fetched.png"
echo "  原图大小：$(wc -c <"$WORK/homework.png") 字节 / 取回：$(wc -c <"$WORK/fetched.png") 字节"
cmp "$WORK/homework.png" "$WORK/fetched.png" || { echo "原图不一致" >&2; exit 1; }

echo "== GET /api/days =="
curl -fsS "$BASE/api/days?from=$DATE&to=$DATE"; echo

echo "== 完成 =="
