import asyncio

from .config import CLAUDE_BIN, CLAUDE_TIMEOUT, MAX_TURNS, SYSTEM_PROMPT_FILE
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
        mem = memory.load(chat_id)
        history = mem["messages"][-(MAX_TURNS * 2):]
        prompt = _build_prompt(history, user_text)
        reply = await _call(prompt)
        mem["messages"].append({"role": "user", "content": user_text})
        mem["messages"].append({"role": "assistant", "content": reply})
        memory.save(chat_id, mem)
        return reply
