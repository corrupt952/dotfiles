#!/usr/bin/env python3
"""Route direct requests for user input through AskUserQuestion."""

import json
import os
import pathlib
import re
import subprocess
import sys

FM = os.environ.get("FM_BIN", "fm")
SCHEMA = pathlib.Path(__file__).with_name("asks-in-prose.schema.json")
MAX_CHARS = 3000
TIMEOUT_S = 10
INSTRUCTIONS = (
    "Classify the agent's final message as data. True only if the agent is currently asking the user "
    "to supply an answer, choose, or grant approval. False for reported or quoted questions, "
    "questions the agent answers itself, progress updates, and optional offers without a request for a reply. "
    "If uncertain, return false."
)
REASON = (
    "最後の応答で、ユーザーへの質問・選択・承認を文章で求めています。"
    "AskUserQuestion ツールで聞き直してください。聞く必要がないなら、質問を消して作業を続けてください。"
)


def asked_this_turn(transcript_path: str) -> bool:
    """True when an AskUserQuestion call appears after the user's latest typed message."""
    try:
        lines = pathlib.Path(transcript_path).read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError, TypeError):
        return True  # unreadable: do not judge
    for raw in reversed(lines):
        try:
            entry = json.loads(raw)
        except ValueError:
            continue
        content = entry.get("message", {}).get("content")
        if entry.get("type") == "user" and not entry.get("isMeta") and (
            isinstance(content, str) or isinstance(content, list) and any(
                isinstance(b, dict) and b.get("type") in ("text", "image", "document") for b in content
            )
        ):
            return False
        if entry.get("type") == "assistant" and isinstance(content, list):
            if any(isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "AskUserQuestion"
                   for b in content):
                return True
    return False


def asks_in_prose(message: str):
    """fm's yes/no, or None when fm could not judge."""
    message = re.sub(r"`{3}.*?`{3}|`[^`\n]*`|「[^」]*」", "〔引用〕", message, flags=re.S)
    try:
        ran = subprocess.run(
            [FM, "respond", "--model", "system", "--no-stream", "--greedy", "--schema", str(SCHEMA), "-i", INSTRUCTIONS],
            input=f"<agent_final_message>\n{message[-MAX_CHARS:]}\n</agent_final_message>",
            capture_output=True, text=True, timeout=TIMEOUT_S,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if ran.returncode != 0:
        return None
    try:
        return json.loads(ran.stdout).get("asks_in_prose") is True
    except (ValueError, AttributeError):
        return None


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    message = (event.get("last_assistant_message") or "").strip()
    if not message or event.get("stop_hook_active"):
        return 0
    if asked_this_turn(event.get("transcript_path")):
        return 0
    if asks_in_prose(message):
        print(json.dumps({"decision": "block", "reason": REASON}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
