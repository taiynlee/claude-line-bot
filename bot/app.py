import asyncio
import json
import logging
import os
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


def _check() -> None:
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

line_bot_api = LineBotApi(LINE_CHANNEL_ACCESS_TOKEN)

try:
    _bot = line_bot_api.get_bot_info()
    log.info(f"Bot userId: {_bot.user_id}（{_bot.display_name}）")
except Exception as e:
    log.warning(f"取得 bot info 失敗：{e}")

app = FastAPI(title="Claude x LINE Bot")

_locks: dict[str, asyncio.Lock] = {}


def _lock(chat_id: str) -> asyncio.Lock:
    if chat_id not in _locks:
        _locks[chat_id] = asyncio.Lock()
    return _locks[chat_id]


def _leave_chat(chat_id: str, src_type: str) -> None:
    if src_type == "group":
        line_bot_api.leave_group(chat_id)
    else:
        line_bot_api.leave_room(chat_id)


@app.get("/")
def root():
    return {"status": "ok", "service": "claude-line-bot"}


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
                _leave_chat(gid, src_type)
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
                _leave_chat(chat_id, src_type)
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

    msgs = [TextSendMessage(text=c) for c in split_for_line(reply)]
    # reply_message 免費不限量，但 replyToken 有時效；失敗才 fallback push_message
    if reply_token:
        try:
            line_bot_api.reply_message(reply_token, msgs[:5])
            if len(msgs) > 5:
                line_bot_api.push_message(push_target, msgs[5:])
            return
        except Exception:
            pass
    line_bot_api.push_message(push_target, msgs)


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
