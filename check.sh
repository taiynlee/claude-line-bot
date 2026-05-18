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

notify_line() {
  [ -z "${LINE_CHANNEL_ACCESS_TOKEN:-}" ] && return
  [ -z "${NOTIFY_USER_ID:-}" ] && return
  curl -s -X POST https://api.line.me/v2/bot/message/push \
    -H "Authorization: Bearer $LINE_CHANNEL_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"to\":\"$NOTIFY_USER_ID\",\"messages\":[{\"type\":\"text\",\"text\":\"🚨 Bot 警報\\n$1\"}]}" > /dev/null
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
    notify_line "Bot 重啟失敗，請手動處理。\n原因請查 $BOT_LOG"
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

# ── 0. 刷新 Claude token（不足 1 小時自動刷新）
"$UV_BIN" run python refresh_token.py 2>&1 | while IFS= read -r line; do log "$line"; done

# ── 1. 檢查 Bot
if curl -sf http://localhost:"$BOT_PORT"/ > /dev/null 2>&1; then
  log "✅ Bot OK"
else
  restart_bot || exit 1
fi

# ── 2. 檢查 ngrok（先取 URL，再實際打洞確認 tunnel 真的通）
NGROK_URL=$(get_ngrok_url 10)
_tunnel_ok() {
  [ -n "$NGROK_URL" ] && curl -sf --max-time 8 "$NGROK_URL" > /dev/null 2>&1
}

if ! _tunnel_ok; then
  if [ -z "$NGROK_URL" ]; then
    log "⚠️  ngrok 無法取得 URL，重啟中..."
  else
    log "⚠️  ngrok tunnel 無回應（heartbeat 斷線），重啟中..."
  fi
  restart_ngrok
  NGROK_URL=$(get_ngrok_url 10)
  if [ -z "$NGROK_URL" ]; then
    log "❌ ngrok 重啟失敗，無法取得 URL"
    notify_line "ngrok 重啟失敗，無法取得 tunnel URL"
    exit 1
  fi
  if ! _tunnel_ok; then
    log "❌ ngrok 重啟後 tunnel 仍無回應，請手動檢查"
    notify_line "ngrok tunnel 重啟後仍無回應，請手動處理"
    exit 1
  fi
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
