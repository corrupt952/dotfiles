#!/usr/bin/env python3
import json
import pathlib
import subprocess
import sys

HOOK = pathlib.Path(__file__).with_name("stop-english-end.py")

CASES = [
    ("english-only", "Split into simpler commands.", False, "block"),
    ("japanese-then-english-last", "日本語で報告しました。\n\nThe ruleset requires only CI Result.", False, "block"),
    ("english-then-japanese-last", "Merged #86.\n\n日本語で続けます。", False, "allow"),
    ("japanese", "日本語で書き直しました。", False, "allow"),
    ("mixed-last-line", "PR #86 をマージしました（5fecc9f）。", False, "allow"),
    ("code-block-last", "結果です。\n```\ncargo deny check\n```", False, "allow"),
    ("title-in-backticks-last", "出した PR です。\n- `feat!: make init and version subcommands`", False, "allow"),
    ("link-last", "出典です。\n- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks.md)", False, "allow"),
    ("url-only", "https://github.com/tang3cko/Caim/pull/86", False, "allow"),
    ("english-with-code-last", "日本語です。\nRun `cargo test` before merging.", False, "block"),
    ("empty", "", False, "allow"),
    ("again-after-block", "Still English.", True, "warn"),
]


def verdict(message: str, active: bool) -> str:
    event = {"hook_event_name": "Stop", "stop_hook_active": active, "last_assistant_message": message}
    ran = subprocess.run([sys.executable, str(HOOK)], input=json.dumps(event), capture_output=True, text=True)
    if ran.returncode != 0:
        return "error: " + ran.stderr.strip()
    if not ran.stdout.strip():
        return "allow"
    out = json.loads(ran.stdout)
    if out.get("decision") == "block":
        return "block"
    return "warn" if out.get("systemMessage") else "other"


def main() -> int:
    failed = 0
    for name, message, active, expected in CASES:
        got = verdict(message, active)
        if got == expected:
            print(f"VERDICT PASS {name}")
        else:
            print(f"VERDICT FAIL {name}: expected {expected}, got {got}")
            failed = 1
    return failed


if __name__ == "__main__":
    sys.exit(main())
