#!/usr/bin/env python3
"""Request one Japanese rewrite when the final prose line ends in English."""

import json
import re
import sys

CODE_BLOCK = re.compile(r"```.*?```", re.S)
INLINE_CODE = re.compile(r"`[^`\n]*`")
LINK = re.compile(r"\[[^\]]*\]\([^)]*\)")
URL = re.compile(r"https?://\S+")
LATIN = re.compile(r"[A-Za-z]")
JAPANESE = re.compile(r"[぀-ヿ㐀-䶿一-鿿ｦ-ﾟ]")

REASON = "最後の応答が英語で終わっています。日本語で書き直してください。"
WARNING = "最後の応答が英語で終わったまま、ターンが終わりました。"


def ends_in_english(text: str) -> bool:
    for pattern in (CODE_BLOCK, INLINE_CODE, LINK, URL):
        text = pattern.sub(" ", text)
    lines = [line for line in text.splitlines() if LATIN.search(line) or JAPANESE.search(line)]
    if not lines:
        return False
    last = lines[-1]
    return bool(LATIN.search(last)) and not JAPANESE.search(last)


def main() -> int:
    event = json.load(sys.stdin)
    if not ends_in_english(event.get("last_assistant_message") or ""):
        return 0
    if event.get("stop_hook_active"):
        print(json.dumps({"systemMessage": WARNING}, ensure_ascii=False))
        return 0
    print(json.dumps({"decision": "block", "reason": REASON}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
