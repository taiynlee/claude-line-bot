#!/usr/bin/env bash
# Shared helpers — source this file, do not execute directly.

BOT_PORT=8000
BOT_LOG=/tmp/bot.log
NGROK_LOG=/tmp/ngrok-bot.log
PIDS_FILE=/tmp/.bot-pids
CHECK_LOG=/tmp/bot-check.log

UV_BIN="${UV_BIN:-$HOME/.local/bin/uv}"
NGROK_BIN="${NGROK_BIN:-$HOME/.local/bin/ngrok}"

load_env() {
  [ -f .env ] && export $(grep -v '^#' .env | xargs)
}

_start_bot() {
  nohup "$UV_BIN" run uvicorn main:app --host 0.0.0.0 --port "$BOT_PORT" \
    >> "$BOT_LOG" 2>&1 &
  echo $!
}

_start_ngrok() {
  setsid "$NGROK_BIN" http "$BOT_PORT" --log "$NGROK_LOG" \
    < /dev/null > /dev/null 2>&1 &
  echo $!
}

get_ngrok_url() {
  local max="${1:-15}"
  for i in $(seq 1 "$max"); do
    local url
    url=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | \
      python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)['tunnels']
    print(next(t['public_url'] for t in d if t['proto'] == 'https'))
except Exception:
    print('')
" 2>/dev/null || true)
    [ -n "$url" ] && { echo "$url"; return 0; }
    sleep 1
  done
  echo ""
}

update_line_webhook() {
  curl -s -X PUT https://api.line.me/v2/bot/channel/webhook/endpoint \
    -H "Authorization: Bearer $LINE_CHANNEL_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"endpoint\":\"$1\"}" > /dev/null
}

save_pids() {
  echo "$1 $2" > "$PIDS_FILE"
}

kill_all() {
  pkill -f "uvicorn main:app" 2>/dev/null || true
  pkill -f "ngrok http"       2>/dev/null || true
  rm -f "$PIDS_FILE"
}
