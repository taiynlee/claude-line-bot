#!/usr/bin/env bash
# 健康檢查：自動偵測並重啟異常元件
# 可手動執行，或由 cron 定期呼叫
cd "$(dirname "$0")"
source "$(dirname "$0")/lib.sh"
load_env

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg" | tee -a "$CHECK_LOG"
}

_read_pid() {
  awk "{print \$$1}" "$PIDS_FILE" 2>/dev/null || echo 0
}

restart_bot() {
  log "⚠️  Bot 異常，重啟中..."
  pkill -f "uvicorn main:app" 2>/dev/null || true
  sleep 1
  local pid; pid=$(_start_bot)
  save_pids "$pid" "$(_read_pid 2)"
  sleep 3
  if curl -sf http://localhost:"$BOT_PORT"/ > /dev/null 2>&1; then
    log "✅ Bot 重啟成功"
  else
    log "❌ Bot 重啟失敗，請手動檢查 $BOT_LOG"
    return 1
  fi
}

restart_ngrok() {
  log "⚠️  ngrok 異常，重啟中..."
  pkill -f "ngrok http" 2>/dev/null || true
  sleep 1
  local pid; pid=$(_start_ngrok)
  save_pids "$(_read_pid 1)" "$pid"
  sleep 5
}

# ── 1. 檢查 Bot
if curl -sf http://localhost:"$BOT_PORT"/ > /dev/null 2>&1; then
  log "✅ Bot OK"
else
  restart_bot || exit 1
fi

# ── 2. 檢查 ngrok
NGROK_URL=$(get_ngrok_url 10)
if [ -z "$NGROK_URL" ]; then
  restart_ngrok
  NGROK_URL=$(get_ngrok_url 10)
  [ -n "$NGROK_URL" ] || { log "❌ ngrok 重啟失敗，無法取得 URL"; exit 1; }
  log "✅ ngrok 重啟成功：$NGROK_URL"
else
  log "✅ ngrok OK：$NGROK_URL"
fi

# ── 3. 檢查 LINE webhook
EXPECTED="$NGROK_URL/webhook"
CURRENT=$(curl -s https://api.line.me/v2/bot/channel/webhook/endpoint \
  -H "Authorization: Bearer $LINE_CHANNEL_ACCESS_TOKEN" 2>/dev/null | \
  python3 -c "import sys,json; print(json.load(sys.stdin).get('endpoint',''))" 2>/dev/null || true)

if [ "$CURRENT" != "$EXPECTED" ]; then
  log "⚠️  LINE webhook 不符，更新中..."
  update_line_webhook "$EXPECTED"
  log "✅ LINE webhook 已更新 → $EXPECTED"
else
  log "✅ LINE webhook OK"
fi

log "🟢 健康檢查完成"
