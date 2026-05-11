#!/usr/bin/env python3
"""Refresh Claude Code OAuth token before it expires.

Reads credentials from ~/.claude/.credentials.json, refreshes the access token,
and writes back to all known credential locations.
"""
import json
import os
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

OAUTH_ENDPOINT = "https://claude.ai/v1/oauth/token"
CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
USER_AGENT = "Mozilla/5.0 claude-code/2.1.138"
REFRESH_THRESHOLD_MS = 3600 * 1000  # refresh when < 1 hour left

def _cred_paths() -> list[Path]:
    paths = [Path.home() / ".claude" / ".credentials.json"]
    # Under WSL, also check Windows-side credentials (scan /mnt/c/Users/)
    win_users = Path("/mnt/c/Users")
    if win_users.is_dir():
        for p in win_users.iterdir():
            cred = p / ".claude" / ".credentials.json"
            if cred.exists():
                paths.insert(0, cred)
                break
    return paths


def load_creds(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def do_refresh(refresh_token: str) -> dict:
    payload = json.dumps({
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
        "client_id": CLIENT_ID,
    }).encode()
    req = urllib.request.Request(
        OAUTH_ENDPOINT,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def main() -> None:
    creds = None
    for p in _cred_paths():
        creds = load_creds(p)
        if creds:
            break

    if not creds:
        print("❌ 找不到 credentials 檔案", file=sys.stderr)
        sys.exit(1)

    oauth = creds.get("claudeAiOauth", {})
    expires_at = oauth.get("expiresAt", 0)
    now_ms = int(time.time() * 1000)
    remaining_ms = expires_at - now_ms

    if remaining_ms > REFRESH_THRESHOLD_MS:
        print(f"✅ Token 仍有效，{remaining_ms / 3600000:.1f} 小時後到期，無需刷新")
        return

    status = "已過期" if remaining_ms < 0 else f"{remaining_ms / 60000:.0f} 分鐘後到期"
    print(f"⚠️  Token {status}，刷新中...")

    refresh_token = oauth.get("refreshToken")
    if not refresh_token:
        print("❌ 無 refreshToken，請重新執行 claude login", file=sys.stderr)
        sys.exit(1)

    try:
        result = do_refresh(refresh_token)
    except urllib.error.HTTPError as e:
        print(f"❌ HTTP {e.code}：{e.read().decode()}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"❌ 刷新失敗：{e}", file=sys.stderr)
        sys.exit(1)

    if "error" in result:
        print(f"❌ API 錯誤：{result['error']}", file=sys.stderr)
        sys.exit(1)

    new_access = result["access_token"]
    expires_in = result.get("expires_in", 3600)
    new_expires_at = now_ms + expires_in * 1000
    new_refresh = result.get("refresh_token", refresh_token)

    for p in _cred_paths():
        data = load_creds(p)
        if not data:
            continue
        data["claudeAiOauth"]["accessToken"] = new_access
        data["claudeAiOauth"]["expiresAt"] = new_expires_at
        data["claudeAiOauth"]["refreshToken"] = new_refresh
        p.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"✅ 已更新：{p}")

    print(f"✅ Token 刷新成功，{expires_in / 3600:.1f} 小時後到期")


if __name__ == "__main__":
    main()
