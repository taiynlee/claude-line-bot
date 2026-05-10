#!/usr/bin/env bash
# 一鍵啟動：bot + ngrok + 自動更新 LINE webhook
set -euo pipefail
cd "$(dirname "$0")"

NGROK_BIN="${NGROK_BIN:-$HOME/.local/bin/ngrok}"

# 讀 .env
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# 確認前置條件
[ -f .env ]            || { echo "❌ .env 不存在，先複製 .env.example"; exit 1; }
[ -n "${LINE_CHANNEL_ACCESS_TOKEN:-}" ] || { echo "❌ LINE_CHANNEL_ACCESS_TOKEN 未設定"; exit 1; }
command -v uv          >/dev/null || { echo "❌ uv 未安裝"; exit 1; }
command -v "$NGROK_BIN" >/dev/null 2>&1 || { echo "❌ ngrok 找不到 ($NGROK_BIN)"; exit 1; }

echo "▶ 啟動 bot (port 8000)..."
uv run uvicorn main:app --host 0.0.0.0 --port 8000 &
BOT_PID=$!

echo "▶ 啟動 ngrok..."
"$NGROK_BIN" http 8000 > /tmp/ngrok-bot.log 2>&1 &
NGROK_PID=$!
sleep 4

echo "▶ 取得 ngrok URL..."
NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | python3 -c "
import sys, json
tunnels = json.load(sys.stdin)['tunnels']
print(next(t['public_url'] for t in tunnels if t['proto'] == 'https'))
")

echo "▶ 更新 LINE webhook → $NGROK_URL/webhook"
curl -s -X PUT https://api.line.me/v2/bot/channel/webhook/endpoint \
  -H "Authorization: Bearer $LINE_CHANNEL_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"endpoint\":\"$NGROK_URL/webhook\"}" > /dev/null

echo "$BOT_PID $NGROK_PID" > /tmp/.bot-pids

echo ""
echo "✅ Bot 已就緒"
echo "   Webhook : $NGROK_URL/webhook"
echo "   傳 /hello 給 bot 測試"
echo ""
echo "停止請執行 ./stop.sh 或按 Ctrl+C"

trap "kill $BOT_PID $NGROK_PID 2>/dev/null; rm -f /tmp/.bot-pids; echo '停止。'" EXIT
wait $BOT_PID
