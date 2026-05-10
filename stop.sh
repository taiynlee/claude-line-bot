#!/usr/bin/env bash
cd "$(dirname "$0")"
source "$(dirname "$0")/lib.sh"
kill_all
echo "✅ 已停止"
