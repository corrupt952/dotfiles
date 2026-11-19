#!/usr/bin/env python3
"""Runs the Stop hook as Claude Code does and prints one verdict line per case.

fm is replaced by a stub (FM_BIN) that answers from a file, so the cases test the hook's own logic:
whether AskUserQuestion was used this turn, what goes to fm, and what happens when fm fails.
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile

HOOK = pathlib.Path(__file__).with_name("stop-ask-in-prose.py")

STUB = """#!/bin/sh
cat > "$STUB_DIR/input.txt"
if [ -f "$STUB_DIR/fail" ]; then echo "Error: The model's safety guardrails were triggered." >&2; exit 1; fi
cat "$STUB_DIR/answer.json"
"""


def transcript(path, turn_tools, user_content):
    """Writes a transcript: an older turn that used AskUserQuestion, then the current turn."""
    lines = [
        {"type": "user", "message": {"role": "user", "content": "前の依頼"}},
        {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "AskUserQuestion", "input": {}}]}},
        {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "content": "answered"}]}},
        {"type": "user", "message": {"role": "user", "content": user_content}},
    ]
    for name in turn_tools:
        lines.append({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": name, "input": {}}]}})
        lines.append({"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "content": "ok"}]}})
    lines.append({"type": "assistant", "message": {"content": [{"type": "text", "text": "最後の応答"}]}})
    path.write_text("\n".join(json.dumps(x, ensure_ascii=False) for x in lines) + "\n")


def run(case, tmp):
    stub_dir = tmp / case["name"]
    stub_dir.mkdir()
    (stub_dir / "fm").write_text(STUB)
    (stub_dir / "fm").chmod(0o755)
    (stub_dir / "answer.json").write_text(json.dumps({"asks_in_prose": case.get("fm", False)}))
    if case.get("fm_fails"):
        (stub_dir / "fail").write_text("")
    tpath = stub_dir / "t.jsonl"
    transcript(tpath, case.get("tools", []), case.get("user", "今の依頼"))
    event = {"hook_event_name": "Stop", "stop_hook_active": case.get("active", False),
             "transcript_path": str(tpath), "last_assistant_message": case["message"]}
    env = dict(os.environ, FM_BIN=str(stub_dir / "fm"), STUB_DIR=str(stub_dir))
    ran = subprocess.run([sys.executable, str(HOOK)], input=json.dumps(event), capture_output=True, text=True, env=env)
    if ran.returncode != 0:
        return "error: " + ran.stderr.strip()[:200], stub_dir
    out = json.loads(ran.stdout) if ran.stdout.strip() else {}
    if out.get("decision") == "block":
        return "block", stub_dir
    return ("warn" if out.get("systemMessage") else "allow"), stub_dir


CASES = [
    {"name": "block-array-boundary", "user": [{"type": "text", "text": "今の依頼"}], "message": "どちら？", "fm": True, "expect": "block"},
    {"name": "invalid-model-value", "message": "終了。", "fm": "false", "expect": "allow"},
    {"name": "asks-in-prose", "message": "どちらにしますか？", "fm": True, "expect": "block"},
    {"name": "no-question", "message": "直しました。", "fm": False, "expect": "allow"},
    {"name": "asked-with-tool-this-turn", "message": "どちらにしますか？", "fm": True, "tools": ["AskUserQuestion"], "expect": "allow"},
    {"name": "other-tools-this-turn", "message": "どちらにしますか？", "fm": True, "tools": ["Bash", "Read"], "expect": "block"},
    {"name": "fm-fails", "message": "どちらにしますか？", "fm_fails": True, "expect": "allow"},
    {"name": "again-after-block", "message": "どちらにしますか？", "fm": True, "active": True, "expect": "allow"},
    {"name": "empty-message", "message": "", "fm": True, "expect": "allow"},
]


def main():
    failed = 0
    with tempfile.TemporaryDirectory() as d:
        tmp = pathlib.Path(d)
        for case in CASES:
            got, stub_dir = run(case, tmp)
            ok = got == case["expect"]
            if ok and case["name"] == "asks-in-prose":
                sent = (stub_dir / "input.txt").read_text() if (stub_dir / "input.txt").exists() else ""
                if case["message"] not in sent:
                    ok, got = False, "fm did not receive the message"
            print(f"VERDICT {'PASS' if ok else 'FAIL'} {case['name']}" + ("" if ok else f": expected {case['expect']}, got {got}"))
            failed |= not ok
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
