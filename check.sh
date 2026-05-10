#!/usr/bin/env bash
# 健康檢查：自動偵測並重啟異常元件
# 可手動執行，或由 cron 定期呼叫

cd "$(dirname "$0")"

UV_BIN="${UV_BIN:-$HOME/.local/bin/uv}"
NGROK_BIN="${NGROK_BIN:-$HOME/.local/bin/ngrok}"
CHECK_LOG=/tmp/bot-check.log

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg" >> "$CHECK_LOG"
  echo "$msg"
}

restart_bot() {
  log "⚠️  Bot 異常，重啟中..."
  pkill -f "uvicorn main:app" 2>/dev/null || true
  sleep 1
  nohup "$UV_BIN" run uvicorn main:app --host 0.0.0.0 --port 8000 \
    >> /tmp/bot.log 2>&1 &
  echo $! > /tmp/.bot-uvicorn.pid
  sleep 3
  if curl -sf http://localhost:8000/ > /dev/null 2>&1; then
    log "✅ Bot 重啟成功"
    return 0
  else
    log "❌ Bot 重啟失敗，請手動檢查 /tmp/bot.log"
    return 1
  fi
}

restart_ngrok() {
  log "⚠️  ngrok 異常，重啟中..."
  pkill -f "ngrok http" 2>/dev/null || true
  sleep 1
  setsid "$NGROK_BIN" http 8000 --log /tmp/ngrok-bot.log \
    < /dev/null > /dev/null 2>&1 &
  echo $! > /tmp/.ngrok.pid
  sleep 5
}

get_ngrok_url() {
  for i in $(seq 1 10); do
    local url
    url=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | \
      python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)['tunnels']
    print(next(t['public_url'] for t in d if t['proto'] == 'https'))
except:
    print('')
" 2>/dev/null || true)
    [ -n "$url" ] && { echo "$url"; return 0; }
    sleep 1
  done
  echo ""
}

# ── 1. 檢查 Bot ──────────────────────────────────────────────
if curl -sf http://localhost:8000/ > /dev/null 2>&1; then
  log "✅ Bot OK"
else
  restart_bot || exit 1
fi

# ── 2. 檢查 ngrok ────────────────────────────────────────────
NGROK_URL=$(get_ngrok_url)
if [ -z "$NGROK_URL" ]; then
  restart_ngrok
  NGROK_URL=$(get_ngrok_url)
  if [ -z "$NGROK_URL" ]; then
    log "❌ ngrok 重啟失敗，無法取得 URL"
    exit 1
  fi
  log "✅ ngrok 重啟成功：$NGROK_URL"
else
  log "✅ ngrok OK：$NGROK_URL"
fi

# ── 3. 檢查 LINE webhook ─────────────────────────────────────
EXPECTED="$NGROK_URL/webhook"
CURRENT=$(curl -s https://api.line.me/v2/bot/channel/webhook/endpoint \
  -H "Authorization: Bearer $LINE_CHANNEL_ACCESS_TOKEN" 2>/dev/null | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('endpoint',''))" 2>/dev/null || true)

if [ "$CURRENT" != "$EXPECTED" ]; then
  log "⚠️  LINE webhook 不符，更新中..."
  curl -s -X PUT https://api.line.me/v2/bot/channel/webhook/endpoint \
    -H "Authorization: Bearer $LINE_CHANNEL_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"endpoint\":\"$EXPECTED\"}" > /dev/null
  log "✅ LINE webhook 已更新 → $EXPECTED"
else
  log "✅ LINE webhook OK"
fi

log "🟢 健康檢查完成"
