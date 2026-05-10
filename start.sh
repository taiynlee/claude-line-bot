#!/usr/bin/env bash
# 一鍵啟動：bot + ngrok + 自動更新 LINE webhook（背景執行，關終端不死）
set -euo pipefail
cd "$(dirname "$0")"

NGROK_BIN="${NGROK_BIN:-$HOME/.local/bin/ngrok}"
UV_BIN="${UV_BIN:-$HOME/.local/bin/uv}"

# 讀 .env
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# 確認前置條件
[ -f .env ]            || { echo "❌ .env 不存在，先複製 .env.example"; exit 1; }
[ -n "${LINE_CHANNEL_ACCESS_TOKEN:-}" ] || { echo "❌ LINE_CHANNEL_ACCESS_TOKEN 未設定"; exit 1; }
[ -x "$UV_BIN" ]       || { echo "❌ uv 找不到 ($UV_BIN)"; exit 1; }
[ -x "$NGROK_BIN" ]    || { echo "❌ ngrok 找不到 ($NGROK_BIN)"; exit 1; }

# 停掉舊的（如果有的話）
if [ -f /tmp/.bot-pids ]; then
  read -r OLD_BOT OLD_NGROK < /tmp/.bot-pids
  kill "$OLD_BOT" "$OLD_NGROK" 2>/dev/null || true
  rm -f /tmp/.bot-pids
fi
pkill -f "uvicorn main:app" 2>/dev/null || true
sleep 1

echo "▶ 啟動 bot (port 8000)..."
nohup "$UV_BIN" run uvicorn main:app --host 0.0.0.0 --port 8000 \
  > /tmp/bot.log 2>&1 &
BOT_PID=$!

echo "▶ 啟動 ngrok..."
setsid "$NGROK_BIN" http 8000 --log /tmp/ngrok-bot.log \
  < /dev/null > /dev/null 2>&1 &
NGROK_PID=$!

echo "$BOT_PID $NGROK_PID" > /tmp/.bot-pids

# 等 ngrok 就緒
echo "▶ 等待 ngrok tunnel..."
for i in $(seq 1 15); do
  NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin)['tunnels']; print(next((t['public_url'] for t in d if t['proto']=='https'),''))" 2>/dev/null || true)
  [ -n "$NGROK_URL" ] && break
  sleep 1
done

[ -n "${NGROK_URL:-}" ] || { echo "❌ ngrok 啟動逾時"; exit 1; }

echo "▶ 更新 LINE webhook → $NGROK_URL/webhook"
curl -s -X PUT https://api.line.me/v2/bot/channel/webhook/endpoint \
  -H "Authorization: Bearer $LINE_CHANNEL_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"endpoint\":\"$NGROK_URL/webhook\"}" > /dev/null

echo ""
echo "✅ Bot 已就緒（背景執行，關終端不影響）"
echo "   Webhook : $NGROK_URL/webhook"
echo "   Log     : tail -f /tmp/bot.log"
echo "   停止    : bash stop.sh"
