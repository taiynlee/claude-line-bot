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
