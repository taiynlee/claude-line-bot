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
    mem["messages"] = mem["messages"][-(MAX_TURNS * 2):]
    _path(chat_id).write_text(
        json.dumps(mem, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def clear(chat_id: str) -> None:
    _path(chat_id).unlink(missing_ok=True)


def recent_messages(chat_id: str) -> list[dict]:
    return load(chat_id)["messages"][-(MAX_TURNS * 2):]
