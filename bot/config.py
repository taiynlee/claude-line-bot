import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

LINE_CHANNEL_ACCESS_TOKEN = os.getenv("LINE_CHANNEL_ACCESS_TOKEN", "")
LINE_CHANNEL_SECRET = os.getenv("LINE_CHANNEL_SECRET", "")
def _id_set(key: str) -> set[str]:
    return {v.strip() for v in os.getenv(key, "").split(",") if v.strip()}

ALLOWED_USER_IDS = _id_set("ALLOWED_USER_IDS")
ALLOWED_GROUP_IDS = _id_set("ALLOWED_GROUP_IDS")
CLAUDE_BIN = os.getenv("CLAUDE_BIN", "claude")
CLAUDE_TIMEOUT = int(os.getenv("CLAUDE_TIMEOUT", "120"))
MAX_TURNS = int(os.getenv("MAX_TURNS", "20"))

BASE_DIR = Path(__file__).parent.parent
SYSTEM_PROMPT_FILE = BASE_DIR / "system_prompt.md"
MEMORY_DIR = BASE_DIR / "memory"
LOG_DIR = BASE_DIR / "logs"

MEMORY_DIR.mkdir(exist_ok=True)
LOG_DIR.mkdir(exist_ok=True)
