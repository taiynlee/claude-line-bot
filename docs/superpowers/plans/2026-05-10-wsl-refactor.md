# WSL Refactor & uv Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 將 claude-line-bot 從 Windows 單檔架構重構為 WSL 上可穩定運行的模組化專案，使用 uv 管理套件，並推送到 GitHub。

**Architecture:** FastAPI app 拆分為 `bot/` package（config / memory / claude_client / line_handler / app），入口為 `main.py`，以 `uv run uvicorn` 啟動。所有 Windows-only 腳本刪除，改用 Makefile + shell scripts。

**Tech Stack:** Python 3.11, FastAPI, uvicorn, line-bot-sdk, python-dotenv, uv

---

## 檔案結構對照

| 動作 | 路徑 |
|---|---|
| 刪除 | `bot.py`, `requirements.txt`, `setup.ps1`, `setup.bat`, `install.ps1`, `install.bat`, `start.ps1`, `start.bat` |
| 刪除 | `tmp_dram.py`, `tmp_qige.py`, `tmp_quote.py`, `ta_6488.py` |
| 清空 | `logs/`, `memory/` 目錄內容 |
| 建立 | `pyproject.toml` |
| 建立 | `bot/__init__.py` |
| 建立 | `bot/config.py` |
| 建立 | `bot/memory.py` |
| 建立 | `bot/claude_client.py` |
| 建立 | `bot/line_handler.py` |
| 建立 | `bot/app.py` |
| 建立 | `main.py` |
| 建立 | `Makefile` |
| 修改 | `system_prompt.md`（更新 Python 路徑） |
| 修改 | `.gitignore`（加入 uv 相關項目） |
| 修改 | `.env.example`（加入 WSL 說明） |
| 建立 | `README.md` |

---

## Task 1: 清理冗餘檔案

**Files:**
- Delete: `bot.py`, `requirements.txt`
- Delete: `setup.ps1`, `setup.bat`, `install.ps1`, `install.bat`, `start.ps1`, `start.bat`
- Delete: `tmp_dram.py`, `tmp_qige.py`, `tmp_quote.py`, `ta_6488.py`
- Clear: `logs/`, `memory/` contents

- [ ] **Step 1: 刪除 Windows 腳本和冗餘 Python 檔**

```bash
cd /home/tommy0322/claude-line-bot
rm -f bot.py requirements.txt
rm -f setup.ps1 setup.bat install.ps1 install.bat start.ps1 start.bat
rm -f tmp_dram.py tmp_qige.py tmp_quote.py ta_6488.py
rm -f logs/*.log memory/*.json
rm -rf __pycache__ .venv
```

- [ ] **Step 2: 確認清理結果**

```bash
ls -la
```

Expected output: 只剩下 `.env`（如果有）、`.env.example`、`.gitignore`、`system_prompt.md`、`docs/` 目錄。

---

## Task 2: 建立 uv 專案（pyproject.toml）

**Files:**
- Create: `pyproject.toml`
- Create: `.python-version`

- [ ] **Step 1: 安裝 uv（如果還沒安裝）**

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc  # 或 source ~/.profile
uv --version
```

Expected: `uv 0.x.x`

- [ ] **Step 2: 建立 pyproject.toml**

```toml
[project]
name = "claude-line-bot"
version = "0.1.0"
description = "LINE Bot powered by Claude Code CLI (Pro subscription)"
requires-python = ">=3.11"
dependencies = [
    "fastapi>=0.115.0",
    "uvicorn[standard]>=0.32.0",
    "line-bot-sdk>=3.14.0",
    "python-dotenv>=1.0.0",
]
```

- [ ] **Step 3: 建立 .python-version**

```
3.11
```

- [ ] **Step 4: 初始化 uv 並安裝套件**

```bash
uv sync
```

Expected: 建立 `.venv/` 和 `uv.lock`

- [ ] **Step 5: 驗證套件可 import**

```bash
uv run python -c "import fastapi, uvicorn, linebot; print('OK')"
```

Expected: `OK`

---

## Task 3: 建立 bot/config.py

**Files:**
- Create: `bot/__init__.py`
- Create: `bot/config.py`

- [ ] **Step 1: 建立空的 `bot/__init__.py`**

```python
```

（空檔案）

- [ ] **Step 2: 建立 `bot/config.py`**

```python
import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

LINE_CHANNEL_ACCESS_TOKEN = os.getenv("LINE_CHANNEL_ACCESS_TOKEN", "")
LINE_CHANNEL_SECRET = os.getenv("LINE_CHANNEL_SECRET", "")
ALLOWED_USER_IDS = {
    uid.strip() for uid in os.getenv("ALLOWED_USER_IDS", "").split(",") if uid.strip()
}
ALLOWED_GROUP_IDS = {
    gid.strip() for gid in os.getenv("ALLOWED_GROUP_IDS", "").split(",") if gid.strip()
}
CLAUDE_BIN = os.getenv("CLAUDE_BIN", "claude")
CLAUDE_TIMEOUT = int(os.getenv("CLAUDE_TIMEOUT", "120"))
MAX_TURNS = int(os.getenv("MAX_TURNS", "20"))

BASE_DIR = Path(__file__).parent.parent
SYSTEM_PROMPT_FILE = BASE_DIR / "system_prompt.md"
MEMORY_DIR = BASE_DIR / "memory"
LOG_DIR = BASE_DIR / "logs"

MEMORY_DIR.mkdir(exist_ok=True)
LOG_DIR.mkdir(exist_ok=True)
```

- [ ] **Step 3: 驗證 config 可 import**

```bash
uv run python -c "from bot.config import CLAUDE_BIN; print('config OK:', CLAUDE_BIN)"
```

Expected: `config OK: claude`

---

## Task 4: 建立 bot/memory.py

**Files:**
- Create: `bot/memory.py`

- [ ] **Step 1: 建立 `bot/memory.py`**

```python
import hashlib
import json
from pathlib import Path

from .config import MAX_TURNS, MEMORY_DIR


def _path(chat_id: str) -> Path:
    safe = hashlib.sha256(chat_id.encode()).hexdigest()[:16]
    return MEMORY_DIR / f"{safe}.json"


def load(chat_id: str) -> dict:
    p = _path(chat_id)
    if not p.exists():
        return {"messages": []}
    return json.loads(p.read_text(encoding="utf-8"))


def save(chat_id: str, mem: dict) -> None:
    _path(chat_id).write_text(
        json.dumps(mem, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def clear(chat_id: str) -> None:
    _path(chat_id).unlink(missing_ok=True)


def recent_messages(chat_id: str) -> list[dict]:
    return load(chat_id)["messages"][-(MAX_TURNS * 2):]
```

- [ ] **Step 2: 驗證 memory 可 import**

```bash
uv run python -c "from bot.memory import load, save, clear; print('memory OK')"
```

Expected: `memory OK`

---

## Task 5: 建立 bot/claude_client.py

**Files:**
- Create: `bot/claude_client.py`

- [ ] **Step 1: 建立 `bot/claude_client.py`**

```python
import asyncio

from .config import CLAUDE_BIN, CLAUDE_TIMEOUT, SYSTEM_PROMPT_FILE
from . import memory

_SYSTEM_PROMPT = SYSTEM_PROMPT_FILE.read_text(encoding="utf-8")


def _build_prompt(history: list[dict], new_message: str) -> str:
    parts = [_SYSTEM_PROMPT, "\n\n# 對話歷史"]
    if not history:
        parts.append("（這是第一則訊息）")
    else:
        for m in history:
            role = "使用者" if m["role"] == "user" else "你"
            parts.append(f"\n{role}：{m['content']}")
    parts.append(f"\n\n# 使用者剛剛的新訊息\n{new_message}")
    parts.append("\n\n# 你的任務\n直接回覆使用者的新訊息。不要重複問候、不要解釋你在做什麼，直接給答案。")
    return "\n".join(parts)


async def _call(prompt: str) -> str:
    proc = await asyncio.create_subprocess_exec(
        CLAUDE_BIN, "-p", "--dangerously-skip-permissions",
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(input=prompt.encode("utf-8")),
            timeout=CLAUDE_TIMEOUT,
        )
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        raise RuntimeError(f"Claude Code 超過 {CLAUDE_TIMEOUT} 秒沒回應")

    if proc.returncode != 0:
        raise RuntimeError(
            f"Claude Code 回傳非 0：{proc.returncode}\n"
            f"stderr: {stderr.decode(errors='replace')}"
        )
    return stdout.decode("utf-8", errors="replace").strip()


async def chat(chat_id: str, user_text: str, lock: asyncio.Lock) -> str:
    async with lock:
        history = memory.recent_messages(chat_id)
        prompt = _build_prompt(history, user_text)
        reply = await _call(prompt)

        mem = memory.load(chat_id)
        mem["messages"].append({"role": "user", "content": user_text})
        mem["messages"].append({"role": "assistant", "content": reply})
        memory.save(chat_id, mem)
        return reply
```

- [ ] **Step 2: 驗證 claude_client 可 import**

```bash
uv run python -c "from bot.claude_client import chat; print('claude_client OK')"
```

Expected: `claude_client OK`

---

## Task 6: 建立 bot/line_handler.py

**Files:**
- Create: `bot/line_handler.py`

- [ ] **Step 1: 建立 `bot/line_handler.py`**

```python
import base64
import hashlib
import hmac

from .config import LINE_CHANNEL_SECRET

_IGNORED_MENTION_NAMES = {"東南", "Tommy", "min"}


def verify_signature(body: bytes, signature: str) -> bool:
    digest = hmac.new(LINE_CHANNEL_SECRET.encode(), body, hashlib.sha256).digest()
    expected = base64.b64encode(digest).decode()
    return hmac.compare_digest(expected, signature)


def split_for_line(text: str, limit: int = 4900) -> list[str]:
    if len(text) <= limit:
        return [text]
    chunks = []
    while text:
        chunks.append(text[:limit])
        text = text[limit:]
    return chunks[:5]


def _has_ignored_mention(msg: dict) -> bool:
    text = msg.get("text") or ""
    for name in _IGNORED_MENTION_NAMES:
        if f"@{name}" in text:
            return True
    for m in (msg.get("mention") or {}).get("mentionees", []):
        if m.get("displayName") in _IGNORED_MENTION_NAMES:
            return True
    return False


def is_bot_command(msg: dict) -> bool:
    """群組訊息：只有 / 開頭才回應。"""
    if _has_ignored_mention(msg):
        return False
    return (msg.get("text") or "").lstrip().startswith("/")


def strip_mentions(msg: dict) -> str:
    """把 @xxx mention 段落拔掉，保留乾淨文字。"""
    text = msg.get("text", "")
    mentionees = (msg.get("mention") or {}).get("mentionees", [])
    if mentionees:
        for m in sorted(mentionees, key=lambda x: x.get("index", 0), reverse=True):
            i, L = m.get("index", 0), m.get("length", 0)
            text = text[:i] + text[i + L:]
        return text.strip()
    stripped = text.lstrip()
    if stripped.startswith("/"):
        return stripped.strip()
    if stripped.startswith("@"):
        parts = stripped.split(None, 1)
        return parts[1].strip() if len(parts) > 1 else ""
    return text.strip()
```

- [ ] **Step 2: 驗證 line_handler 可 import**

```bash
uv run python -c "from bot.line_handler import verify_signature, is_bot_command; print('line_handler OK')"
```

Expected: `line_handler OK`

---

## Task 7: 建立 bot/app.py

**Files:**
- Create: `bot/app.py`

- [ ] **Step 1: 建立 `bot/app.py`**

```python
import asyncio
import json
import logging
import subprocess
from datetime import datetime

from fastapi import FastAPI, Header, HTTPException, Request
from linebot import LineBotApi
from linebot.models import TextSendMessage

from . import claude_client, memory
from .config import (
    ALLOWED_GROUP_IDS,
    ALLOWED_USER_IDS,
    CLAUDE_BIN,
    CLAUDE_TIMEOUT,
    LINE_CHANNEL_ACCESS_TOKEN,
    LOG_DIR,
    SYSTEM_PROMPT_FILE,
)
from .line_handler import is_bot_command, split_for_line, strip_mentions, verify_signature

# ── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(
            LOG_DIR / f"{datetime.now():%Y-%m-%d}.log", encoding="utf-8"
        ),
        logging.StreamHandler(),
    ],
)
log = logging.getLogger("claude-line-bot")


# ── Startup check ─────────────────────────────────────────────────────────────
def _check() -> None:
    import os
    missing = [
        k for k in ("LINE_CHANNEL_ACCESS_TOKEN", "LINE_CHANNEL_SECRET")
        if not os.getenv(k)
    ]
    if missing:
        raise RuntimeError(f"缺少環境變數：{', '.join(missing)}（請檢查 .env）")
    if not SYSTEM_PROMPT_FILE.exists():
        raise RuntimeError(f"找不到 {SYSTEM_PROMPT_FILE}")
    result = subprocess.run(
        [CLAUDE_BIN, "--version"], capture_output=True, text=True, timeout=10
    )
    if result.returncode != 0:
        raise RuntimeError(f"`{CLAUDE_BIN} --version` 失敗：{result.stderr}")
    log.info(f"Claude Code OK：{result.stdout.strip()}")


_check()

# ── LINE client ───────────────────────────────────────────────────────────────
line_bot_api = LineBotApi(LINE_CHANNEL_ACCESS_TOKEN)

try:
    _bot = line_bot_api.get_bot_info()
    log.info(f"Bot userId: {_bot.user_id}（{_bot.display_name}）")
except Exception as e:
    log.warning(f"取得 bot info 失敗：{e}")

# ── FastAPI ───────────────────────────────────────────────────────────────────
app = FastAPI(title="Claude x LINE Bot")

_locks: dict[str, asyncio.Lock] = {}


def _lock(chat_id: str) -> asyncio.Lock:
    if chat_id not in _locks:
        _locks[chat_id] = asyncio.Lock()
    return _locks[chat_id]


@app.get("/")
def root():
    return {"status": "ok", "service": "claude-line-bot"}


# ── Event handling ────────────────────────────────────────────────────────────
async def _handle_event(event: dict) -> None:
    etype = event.get("type")

    if etype == "join":
        src = event.get("source", {})
        src_type = src.get("type")
        gid = src.get("groupId") or src.get("roomId", "")
        if ALLOWED_GROUP_IDS and gid not in ALLOWED_GROUP_IDS:
            log.warning(f"未授權群組，自動退出：{gid}")
            try:
                line_bot_api.push_message(
                    gid, TextSendMessage(text=f"未授權，自動退出。\ngroupId: {gid}")
                )
            except Exception:
                pass
            try:
                if src_type == "group":
                    line_bot_api.leave_group(gid)
                else:
                    line_bot_api.leave_room(gid)
            except Exception as exc:
                log.exception(f"leave 失敗：{exc}")
        return

    if etype != "message":
        return
    msg = event.get("message", {})
    if msg.get("type") != "text":
        return

    source = event.get("source", {})
    src_type = source.get("type", "user")
    user_id = source.get("userId", "anonymous")
    reply_token = event.get("replyToken")

    if src_type in ("group", "room"):
        chat_id = source.get("groupId") or source.get("roomId", "unknown")
        push_target = chat_id
        if ALLOWED_GROUP_IDS and chat_id not in ALLOWED_GROUP_IDS:
            log.warning(f"未授權群組：{chat_id}")
            try:
                line_bot_api.reply_message(
                    reply_token,
                    TextSendMessage(text=f"未授權\ngroupId: {chat_id}"),
                )
            except Exception:
                pass
            try:
                if src_type == "group":
                    line_bot_api.leave_group(chat_id)
                else:
                    line_bot_api.leave_room(chat_id)
            except Exception:
                pass
            return
        if not is_bot_command(msg):
            return
        user_text = strip_mentions(msg)
        if not user_text:
            return
    else:
        chat_id = user_id
        push_target = user_id
        user_text = msg["text"]
        if not user_text.strip().startswith("/"):
            return
        if ALLOWED_USER_IDS and user_id not in ALLOWED_USER_IDS:
            log.warning(f"未授權 user：{user_id}")
            try:
                line_bot_api.reply_message(
                    reply_token,
                    TextSendMessage(text=f"未授權，你的 userId：\n{user_id}"),
                )
            except Exception:
                pass
            return

    if user_text.strip() in ("/reset", "/清除記憶"):
        memory.clear(chat_id)
        try:
            line_bot_api.reply_message(
                reply_token, TextSendMessage(text="✅ 已清除這個對話的記憶。")
            )
        except Exception:
            line_bot_api.push_message(
                push_target, TextSendMessage(text="✅ 已清除這個對話的記憶。")
            )
        return

    log.info(f"[{src_type}:{chat_id[:8]}] 收到：{user_text[:50]}")

    try:
        reply = await claude_client.chat(chat_id, user_text, _lock(chat_id))
    except asyncio.TimeoutError:
        log.error(f"[{chat_id[:8]}] Claude timeout ({CLAUDE_TIMEOUT}s)")
        reply = f"⚠️ 處理超時（>{CLAUDE_TIMEOUT}s），請稍後再試。"
    except Exception as e:
        log.exception("Claude Code 呼叫失敗")
        reply = f"⚠️ 錯誤：{type(e).__name__}: {e}"

    if not reply or not reply.strip():
        log.warning("Claude 回空字串，改用預設訊息")
        reply = "（Claude 沒有回應，請再試一次）"

    line_bot_api.push_message(
        push_target,
        [TextSendMessage(text=c) for c in split_for_line(reply)],
    )


async def _handle_event_safe(event: dict) -> None:
    try:
        await _handle_event(event)
    except Exception as e:
        log.exception(f"_handle_event 未預期錯誤: {e}")


@app.post("/webhook")
async def webhook(request: Request, x_line_signature: str = Header(None)):
    body = await request.body()
    if not x_line_signature or not verify_signature(body, x_line_signature):
        log.warning("簽章驗證失敗")
        raise HTTPException(status_code=403, detail="Invalid signature")
    payload = json.loads(body.decode("utf-8"))
    for event in payload.get("events", []):
        asyncio.create_task(_handle_event_safe(event))
    return {"status": "ok"}
```

- [ ] **Step 2: 驗證 app 可 import（需要 .env 存在）**

先確認有 `.env`，然後：

```bash
uv run python -c "from bot.app import app; print('app OK')"
```

Expected: `Claude Code OK: x.x.x` + `app OK`

---

## Task 8: 建立 main.py 和 Makefile

**Files:**
- Create: `main.py`
- Create: `Makefile`

- [ ] **Step 1: 建立 `main.py`**

```python
from bot.app import app

__all__ = ["app"]
```

- [ ] **Step 2: 建立 `Makefile`**

```makefile
.PHONY: setup dev start ngrok

setup:
	uv sync
	@if [ ! -f .env ]; then cp .env.example .env && echo ".env created from .env.example"; fi

dev:
	uv run uvicorn main:app --host 0.0.0.0 --port 8000 --reload

start:
	uv run uvicorn main:app --host 0.0.0.0 --port 8000

ngrok:
	ngrok http 8000
```

- [ ] **Step 3: 驗證啟動（測試用，Ctrl+C 停止）**

```bash
uv run uvicorn main:app --host 0.0.0.0 --port 8000
```

Expected: `Claude Code OK: x.x.x` 之後伺服器啟動在 port 8000。

---

## Task 9: 更新 system_prompt.md、.gitignore、.env.example

**Files:**
- Modify: `system_prompt.md`（更新 venv Python 路徑）
- Modify: `.gitignore`（加入 uv 相關）
- Modify: `.env.example`（加入 WSL 說明）

- [ ] **Step 1: 更新 system_prompt.md 的 Python 路徑**

把：
```bash
C:\Users\tommy\Desktop\claude-line-bot\.venv\Scripts\python.exe -c "..."
```
改為：
```bash
/home/tommy0322/claude-line-bot/.venv/bin/python -c "..."
```

- [ ] **Step 2: 更新 `.gitignore`**

```
.env
memory/
logs/
__pycache__/
*.pyc
.venv/
venv/
.pytest_cache/
*.egg-info/
dist/
```

- [ ] **Step 3: 更新 `.env.example`**（加入 WSL CLAUDE_BIN 說明）

```dotenv
# 複製這個檔案為 .env，填入真實值

# ── LINE Messaging API ────────────────────────────────────────────────────────
LINE_CHANNEL_ACCESS_TOKEN=填你的channel-access-token
LINE_CHANNEL_SECRET=填你的channel-secret

# ── 白名單（強烈建議設定）───────────────────────────────────────────────────
# 1對1 對話白名單（逗號分隔）
ALLOWED_USER_IDS=

# 群組白名單（逗號分隔）
ALLOWED_GROUP_IDS=

# ── Claude Code ──────────────────────────────────────────────────────────────
# WSL 內若已安裝 Claude Code（npm install -g @anthropic-ai/claude-code）
# 就用預設 "claude"。如果 PATH 找不到，填完整路徑：
#   /home/<user>/.nvm/versions/node/<ver>/bin/claude
CLAUDE_BIN=claude

# 回應超時秒數（第一次 cold start 可能要 30s+）
CLAUDE_TIMEOUT=120

# 對話歷史保留輪數（一輪 = 一問一答）
MAX_TURNS=20
```

---

## Task 10: 撰寫 README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: 寫 README.md**（詳見下方完整內容，執行時直接寫入）

README 包含：前置需求、安裝、設定 LINE、啟動、找 userId、群組設定、內建指令、故障排除。

---

## Task 11: git init + 建立 GitHub repo + commit

**Files:**
- Create: `.gitignore`（已在 Task 9 更新）

- [ ] **Step 1: 初始化 git**

```bash
cd /home/tommy0322/claude-line-bot
git init
git branch -M main
```

- [ ] **Step 2: 建立 GitHub repo**

```bash
gh repo create claude-line-bot \
  --public \
  --description "LINE Bot powered by Claude Code CLI (Pro subscription), runs on WSL" \
  --source . \
  --remote origin
```

- [ ] **Step 3: 第一次 commit**

```bash
git add pyproject.toml uv.lock .python-version
git add main.py Makefile
git add bot/__init__.py bot/config.py bot/memory.py
git add bot/claude_client.py bot/line_handler.py bot/app.py
git add system_prompt.md .env.example .gitignore README.md
git add docs/
git commit -m "feat: initial WSL modular architecture with uv"
```

- [ ] **Step 4: Push**

```bash
git push -u origin main
```

- [ ] **Step 5: 確認**

```bash
gh repo view taiynlee/claude-line-bot --web
```
