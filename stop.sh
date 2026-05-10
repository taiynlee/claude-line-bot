#!/usr/bin/env bash
if [ -f /tmp/.bot-pids ]; then
  read -r BOT_PID NGROK_PID < /tmp/.bot-pids
  kill "$BOT_PID" "$NGROK_PID" 2>/dev/null && echo "✅ 已停止" || echo "已經停了"
  rm -f /tmp/.bot-pids
else
  pkill -f "uvicorn main:app" 2>/dev/null
  pkill -f ngrok 2>/dev/null
  echo "✅ 已停止"
fi
