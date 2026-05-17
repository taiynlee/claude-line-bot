# Claude × LINE Bot — 專案架構

## 架構圖

```
┌──────────────────────────────────────────────────────────────────┐
│  LINE App（手機）                                                  │
└──────────────────────┬───────────────────────────────────────────┘
                       │ HTTPS POST /webhook
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│  LINE Messaging API（Cloud）                                      │
└──────────────────────┬───────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│  ngrok（WSL）                                                     │
│  https://xxx.ngrok-free.app  ──→  localhost:8000                 │
└──────────────────────┬───────────────────────────────────────────┘
                       │
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│  FastAPI Bot（WSL, port 8000）                                    │
│                                                                   │
│  webhook  →  line_handler          memory/                       │
│              ├─ verify_signature   └─ {hash}.json  per chat      │
│              ├─ is_bot_command                                    │
│              └─ strip_mentions                                    │
│                       │                                          │
│              claude_client                                        │
│              ├─ build_prompt（system_prompt + history）           │
│              └─ subprocess: claude -p --dangerously-skip-...     │
└──────────────────────┬───────────────────────────────────────────┘
                       │ stdin / stdout
                       ▼
┌──────────────────────────────────────────────────────────────────┐
│  Claude Code CLI（WSL, ~/.local/bin/claude）                      │
│  吃 Claude.ai Pro 訂閱額度（$20/月，零 API 費）                    │
└──────────────────────────────────────────────────────────────────┘
```

## 模組結構

```
claude-line-bot/
├── bot/
│   ├── app.py            FastAPI app、webhook route、事件分派
│   ├── claude_client.py  subprocess 呼叫、prompt 組裝、記憶寫入
│   ├── config.py         環境變數（LINE token、Claude bin、限制）
│   ├── line_handler.py   HMAC 驗簽、mention 解析、訊息切割
│   └── memory.py         JSON 讀寫，每個 chat_id 一個檔案
├── main.py               入口（uvicorn main:app）
├── start.sh              一鍵啟動（bot + ngrok + 自動更新 webhook）
├── stop.sh               停止所有服務
├── system_prompt.md      Claude 人格與行為規則
├── pyproject.toml        uv 套件定義
├── Makefile              開發快捷指令
└── plan.md               本文件
```

## 訊息流程

```
使用者傳訊息
    │
    ▼
verify_signature()   ← HMAC-SHA256 驗簽，失敗直接 403
    │
    ▼
_handle_event()
    ├─ join event  → 不在白名單？leave_group / leave_room
    ├─ group msg   → is_bot_command()？否則忽略
    │               strip_mentions() 取乾淨文字
    └─ DM msg      → 以 "/" 開頭才處理；不在白名單？回 userId
            │
            ▼
        /reset？→ memory.clear()
            │
            ▼
        claude_client.chat()
            ├─ memory.load()         讀對話歷史
            ├─ _build_prompt()       組 system_prompt + history + 新訊息
            ├─ claude -p (subprocess) 呼叫 Claude Code
            └─ memory.save()         寫回記憶
            │
            ▼
        line_bot_api.push_message()  最多 4900 字 × 5 則
```

## 啟動方式

```bash
# 一鍵啟動（推薦）
./start.sh

# 保留記憶重啟
KEEP_MEMORY=1 bash start.sh

# 手動分開跑
make dev    # uvicorn --reload
make ngrok  # ngrok http 8000

# 停止
./stop.sh

# 健康檢查（cron 自動每 5 分鐘執行）
bash check.sh
```

## 可靠性設計

### check.sh（cron */5 分鐘）
1. Claude token refresh（剩 < 1 小時才刷）
2. Bot HTTP 健康確認
3. **ngrok 實際連通性測試**（curl tunnel URL，防止 heartbeat 斷線假陽性）
4. LINE webhook 端點同步

### start.sh
- 每次啟動自動 `chmod +x *.sh`（防止 git pull 後權限丟失）

### Windows 電源（Task Scheduler）
- `BotSleepEnable`（00:00）：standby-timeout-ac = 10 分鐘
- `BotSleepDisable`（06:00）：standby-timeout-ac = 0（永不）+ WakeToRun
- 需啟用 wake timer：`powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 1`

## 環境變數（.env）

| 變數 | 說明 | 預設 |
|---|---|---|
| `LINE_CHANNEL_ACCESS_TOKEN` | LINE channel token | 必填 |
| `LINE_CHANNEL_SECRET` | LINE channel secret | 必填 |
| `ALLOWED_USER_IDS` | 1對1 白名單（逗號分隔） | 空 = 不限 |
| `ALLOWED_GROUP_IDS` | 群組白名單（逗號分隔） | 空 = 不允許 |
| `CLAUDE_BIN` | claude 執行檔路徑 | `claude` |
| `CLAUDE_TIMEOUT` | 回應超時秒數 | `120` |
| `MAX_TURNS` | 保留對話輪數 | `20` |

## 詳細實作計畫

見 [docs/superpowers/plans/2026-05-10-wsl-refactor.md](docs/superpowers/plans/2026-05-10-wsl-refactor.md)
