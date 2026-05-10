# Claude × LINE Bot

LINE Bot 接 Claude Code CLI，吃你的 **Claude.ai Pro 訂閱額度**，零 API 費用。運行在 WSL (Ubuntu) 上。

```
LINE 手機 → LINE Messaging API → ngrok → FastAPI (WSL)
                                              ↓
                              subprocess: claude -p
                                              ↓
                                  Claude Code (Pro 額度)
                                              ↓
                                         回傳 LINE
```

## 前置需求

- WSL 2 (Ubuntu 22.04+)
- Node.js（在 WSL 內安裝）
- Claude Code CLI（在 WSL 內安裝並用 Pro 帳號登入）
- [uv](https://docs.astral.sh/uv/)（Python 套件管理）
- [ngrok](https://ngrok.com) 帳號
- LINE Messaging API channel

## 安裝

### 1. 在 WSL 內安裝 Node.js + Claude Code

```bash
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo bash -
sudo apt-get install -y nodejs
npm install -g @anthropic-ai/claude-code
```

登入 Claude Code（用 Claude.ai Pro 帳號）：

```bash
claude
# 選 "Log in with Claude account" → 瀏覽器登入
# 登入後 /exit 退出

# 驗證
claude -p "用繁體中文說一句你好"
```

### 2. 安裝 uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc
```

### 3. Clone 並設定專案

```bash
git clone https://github.com/taiynlee/claude-line-bot.git
cd claude-line-bot
make setup          # uv sync + 建立 .env
```

編輯 `.env`，填入 LINE token：

```bash
nano .env
```

### 4. 建立 LINE Messaging API channel

1. 到 [LINE Developers Console](https://developers.line.biz/console)
2. 建立 Provider → Create channel → **Messaging API**
3. 取得：
   - **Channel access token**（Messaging API 分頁 → Issue）
   - **Channel secret**（Basic settings 分頁）
4. 關閉 **Auto-reply messages**
5. 用手機掃 QR code 加 bot 為好友

## 啟動

開兩個終端機視窗：

```bash
# 視窗 A：bot
make dev        # 開發模式（--reload）
# 或
make start      # 正式模式

# 視窗 B：ngrok
make ngrok
```

複製 ngrok 給的 `https://xxx.ngrok-free.app`，填到 LINE Console：

- **Webhook URL**：`https://xxx.ngrok-free.app/webhook`
- **Use webhook**：開啟
- 按 **Verify** 應該成功

## 找你的 userId

傳任何訊息給 bot（以 `/` 開頭），bot 會回：

```
未授權，你的 userId：Uxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

把 `Uxxx...` 填到 `.env` 的 `ALLOWED_USER_IDS=`，重啟 bot。

## 內建指令

| 指令 | 說明 |
|---|---|
| `/reset` | 清除這個對話的記憶 |
| `/清除記憶` | 同上 |

所有訊息必須以 `/` 開頭才會觸發，其他訊息一律沉默。

## 群組設定

1. LINE Console → Messaging API → **Allow bot to join group chats** 開啟
2. 把 bot 邀進群組
3. 群組內傳 `/test`，bot 回：

   ```
   未授權的群組
   groupId: Cxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```

4. 把 `Cxxx...` 填到 `.env` 的 `ALLOWED_GROUP_IDS=`，重啟 bot
5. 群組內只有 `/` 開頭的訊息才會觸發

## 專案結構

```
claude-line-bot/
├── bot/
│   ├── config.py          # 環境變數設定
│   ├── memory.py          # 對話記憶（JSON）
│   ├── claude_client.py   # Claude Code subprocess
│   ├── line_handler.py    # LINE 簽章驗證、訊息處理
│   └── app.py             # FastAPI app
├── main.py                # 入口
├── system_prompt.md       # Claude 人格設定
├── Makefile               # 常用指令
├── pyproject.toml         # uv 套件設定
└── .env.example           # 環境變數範本
```

## 故障排除

| 症狀 | 修法 |
|---|---|
| `claude: command not found` | WSL 內執行 `npm install -g @anthropic-ai/claude-code`，或在 `.env` 設 `CLAUDE_BIN=完整路徑` |
| 回應超慢（>30s） | Cold start 正常，後續會快。可調高 `CLAUDE_TIMEOUT` |
| LINE 沒收到回覆 | 看 `logs/` 內當天 log，確認 Claude Code 有回覆 |
| ngrok 網址每次變 | 正常（免費版），每次重啟後更新 LINE Console 的 webhook URL |

## 注意事項

- Claude.ai Pro 有用量上限（約每 5 小時重置），自用沒問題，多人 bot 不適合
- bot 有讀寫你 WSL 檔案的能力（Claude Code 有工具權限），傳訊息等同授權操作
