#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source "$(dirname "$0")/lib.sh"
load_env

[ -f .env ]  || { echo "❌ .env 不存在，先複製 .env.example"; exit 1; }
[ -n "${LINE_CHANNEL_ACCESS_TOKEN:-}" ] || { echo "❌ LINE_CHANNEL_ACCESS_TOKEN 未設定"; exit 1; }
[ -x "$UV_BIN" ]    || { echo "❌ uv 找不到 ($UV_BIN)"; exit 1; }
[ -x "$NGROK_BIN" ] || { echo "❌ ngrok 找不到 ($NGROK_BIN)"; exit 1; }

kill_all
sleep 1

echo "▶ 啟動 bot (port $BOT_PORT)..."
BOT_PID=$(_start_bot)

echo "▶ 啟動 ngrok..."
NGROK_PID=$(_start_ngrok)
save_pids "$BOT_PID" "$NGROK_PID"

echo "▶ 等待 ngrok tunnel..."
NGROK_URL=$(get_ngrok_url 15)
[ -n "$NGROK_URL" ] || { echo "❌ ngrok 啟動逾時"; exit 1; }

echo "▶ 更新 LINE webhook → $NGROK_URL/webhook"
update_line_webhook "$NGROK_URL/webhook"

echo ""
echo "✅ Bot 已就緒（背景執行，關終端不影響）"
echo "   Webhook : $NGROK_URL/webhook"
echo "   Log     : tail -f $BOT_LOG"
echo "   停止    : bash stop.sh"
