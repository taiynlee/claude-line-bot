#!/usr/bin/env python3
"""Send a message to a LINE group or user from the command line.

Usage:
    python send.py "訊息內容"
    python send.py -t <group_id|user_id> "訊息內容"
    echo "訊息" | python send.py
"""
import argparse
import sys

from linebot.v3.messaging import (
    ApiClient,
    Configuration,
    MessagingApi,
    PushMessageRequest,
    TextMessage,
)
from linebot.v3.exceptions import InvalidSignatureError
from linebot.v3.messaging.exceptions import ApiException

from bot.config import ALLOWED_GROUP_IDS, ALLOWED_USER_IDS, LINE_CHANNEL_ACCESS_TOKEN


def main() -> None:
    parser = argparse.ArgumentParser(description="Send a LINE message")
    parser.add_argument("message", nargs="?", help="Message text (or pipe via stdin)")
    parser.add_argument("-t", "--to", help="Target group/user ID (default: first allowed group)")
    args = parser.parse_args()

    text = args.message or (sys.stdin.read().strip() if not sys.stdin.isatty() else None)
    if not text:
        parser.error("訊息不能為空（傳入參數或透過 stdin）")

    target = args.to
    if not target:
        if ALLOWED_GROUP_IDS:
            target = next(iter(ALLOWED_GROUP_IDS))
        elif ALLOWED_USER_IDS:
            target = next(iter(ALLOWED_USER_IDS))
        else:
            sys.exit("❌ .env 未設定 ALLOWED_GROUP_IDS 或 ALLOWED_USER_IDS")

    if not LINE_CHANNEL_ACCESS_TOKEN:
        sys.exit("❌ LINE_CHANNEL_ACCESS_TOKEN 未設定")

    config = Configuration(access_token=LINE_CHANNEL_ACCESS_TOKEN)
    with ApiClient(config) as client:
        api = MessagingApi(client)
        try:
            api.push_message(PushMessageRequest(to=target, messages=[TextMessage(text=text)]))
            print(f"✅ 已送出 → {target[:12]}…\n   {text[:60]}{'…' if len(text) > 60 else ''}")
        except ApiException as e:
            sys.exit(f"❌ LINE API 錯誤：{e.status} {e.reason}")


if __name__ == "__main__":
    main()
