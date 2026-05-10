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
