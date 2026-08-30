#!@python3@
"""Breaks the guard on purpose, to see whether the test suite notices.

A development tool, not a CI gate, and deliberately so: every mutation is
anchored to a literal string in the source, so ordinary edits break anchors,
and a stale anchor looks the same as a real gap. The suite's own red means "a
rule stopped matching", and mixing this in would blur that signal.

Usage: python3 modules/claude/claude-bash-guard.mutation.py
"""

from __future__ import annotations

import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
GUARD = "claude-bash-guard.py"
TEST = "claude-bash-guard.test.py"
ORIGINAL = (HERE / GUARD).read_text()

MUTATIONS: dict[str, tuple[str, str]] = {
    "abbrev: marker not reserved": (
        "    head = text[: limit - marker_budget]",
        "    head = text[:limit]",
    ),
    "abbrev: off-by-one at the cap": (
        "    if len(text) <= limit:\n        return text",
        "    if len(text) < limit:\n        return text",
    ),
    "abbrev: omitted count wrong": (
        "{len(text) - len(head)} chars",
        "{len(text)} chars",
    ),
    "abbrev: head budget halved": (
        "    head = text[: limit - marker_budget]",
        "    head = text[: (limit - marker_budget) // 2]",
    ),
    "abbrev: wiring dropped": ("{abbreviate(command.raw)}", "{command.raw}"),
    "shell -c: recursion removed": (
        "        if depth == 0:\n            payload = nested_command(command)",
        "        if False:\n            payload = nested_command(command)",
    ),
    "shell -c: unbounded depth": ("        if depth == 0:", "        if depth < 99:"),
    "shell -c: shell set narrowed": (
        'SHELLS = frozenset({"bash", "sh", "zsh", "dash", "ksh", "fish"})',
        'SHELLS = frozenset({"bash"})',
    ),
    "shell -c: only a bare -c flag": (
        '        if "c" in arg[1:]:',
        '        if arg == "-c":',
    ),
    "shell -c: separator taken as the program": (
        '                if candidate != "--":',
        "                if True:",
    ),
    "interp: back to the two-way flag branch": (
        "        predicate=lambda c: c.has_trailing_short_flag(INLINE_CODE_FLAG[c.program]),",
        "        predicate=lambda c: c.has_trailing_short_flag(\n"
        '            "c" if c.program.startswith("python") else "e"\n'
        "        ),",
    ),
    "interp: set back to the original five": (
        "INTERPRETERS = frozenset(INLINE_CODE_FLAG)",
        'INTERPRETERS = frozenset({"python", "node", "ruby", "perl"})',
    ),
    "interp: version suffix not stripped": (
        '        return VERSION_SUFFIX.sub("", self.name) or self.name',
        "        return self.name",
    ),
    "interp: rules ignore the version-free name": (
        "        if self.names and command.name not in self.names and command.program not in self.names:",
        "        if self.names and command.name not in self.names:",
    ),
    "comments: not recognised at all": (
        '        if char == "#" and at_word_start:',
        "        if False:",
    ),
    "comments: word position ignored": (
        '        if char == "#" and at_word_start:',
        '        if char == "#":',
    ),
    "comments: quoting ignored": (
        "        if char in \"'\\\"\":\n            quote = char",
        "        if False:\n            quote = char",
    ),
    "comments: shlex handles them again": (
        '    lexer.commenters = ""',
        '    lexer.commenters = "#"',
    ),
    "comments: scanner drops a character": (
        "        result.append(char)\n        at_word_start = char.isspace()",
        "        if char != 'x':\n            result.append(char)\n"
        "        at_word_start = char.isspace()",
    ),
    "nix: --command not stripped": (
        '        if tokens and tokens[0] == "nix" and "--command" in tokens:',
        "        if False:",
    ),
    "wrapper: flag value not skipped": (
        '                if flag in value_flags and tokens and not tokens[0].startswith("-"):',
        "                if False:",
    ),
    "wrapper: value table emptied": (
        '    "xargs": frozenset({"-I", "-n", "-P", "-s", "-L", "-E", "-d", "-a"}),',
        '    "xargs": frozenset(),',
    ),
    "wrapper: sudo -h treated as value-taking": (
        '    "sudo": frozenset({"-u", "-g", "-U", "-C", "-p", "-r", "-t"}),',
        '    "sudo": frozenset({"-u", "-g", "-U", "-C", "-p", "-r", "-t", "-h"}),',
    ),
    "wrapper: xargs -i treated as value-taking": (
        '    "xargs": frozenset({"-I", "-n", "-P", "-s", "-L", "-E", "-d", "-a"}),',
        '    "xargs": frozenset({"-I", "-i", "-n", "-P", "-s", "-L", "-E", "-d", "-a"}),',
    ),
    "localhost: userinfo allowed back in": (
        '    r"(?::[^/?#@]*)?(?:[/?#]|$)",',
        '    r"(?::[^/?#]*)?(?:[/?#]|$)",',
    ),
    "localhost: port must be numeric again": (
        '    r"(?::[^/?#@]*)?(?:[/?#]|$)",',
        '    r"(?::[0-9]+)?(?:[/?#]|$)",',
    ),
    "localhost: host no longer pinned": (
        r'    r"(?:\[::1\]|::1|localhost|127(?:\.[0-9]{1,3}){3}|0\.0\.0\.0)"',
        r'    r"(?:\[::1\]|::1|localhost|127(?:\.[0-9]{1,3}){3}|0\.0\.0\.0)[^:/?#]*"',
    ),
    "keychain: rule disabled": (
        '        names=frozenset({"security"}),',
        '        names=frozenset({"__disabled__"}),',
    ),
    "keychain: over-broad, catches cms too": (
        '            "dump-keychain", "find-generic-password", "find-internet-password", "export"',
        '            "dump-keychain", "find-generic-password", "find-internet-password",\n'
        '            "export", "cms", "list-keychains"',
    ),
    "gh: global flag values not skipped": (
        "        elif arg in GH_VALUE_FLAGS:\n            skip = True",
        "        elif False:\n            skip = True",
    ),
    "gh: help not exempted": (
        '    if "help" in set(command.long_flags()) or "-h" in command.args:\n        return False',
        "    if False:\n        return False",
    ),
    "gh: any scheme counts as a fetch target": (
        "        if URL_ARGUMENT.match(arg):",
        '        if "://" in arg:',
    ),
    "gh: github hosts treated as remote too": (
        "    return any(not GITHUB_HOST.search(host.split(\":\")[0]) for host in hosts)",
        "    return bool(hosts)",
    ),
    "gh: auth status --show-token not caught": (
        '            and ("show-token" in set(c.long_flags()) or c.has_short_letter("t"))',
        "            and False",
    ),
    "gh: visibility value ignored": (
        '        and (flag_value(c, "--visibility") or "").lower() == "public",',
        "        and True,",
    ),
    "gh: visibility compared case-sensitively": (
        '        and (flag_value(c, "--visibility") or "").lower() == "public",',
        '        and flag_value(c, "--visibility") == "public",',
    ),
    "gh ask: ci-config becomes a deny": (
        '        id="gh-ci-config",\n        names=frozenset({"gh"}),\n        decision="ask",',
        '        id="gh-ci-config",\n        names=frozenset({"gh"}),\n        decision="deny",',
    ),
    "gh ask: repo sync force flag ignored": (
        '        and ("force" in set(c.long_flags()) or c.has_short_letter("f")),',
        "        and True,",
    ),
    "gh ask: run delete not covered": (
        '            ("run", "delete"),',
        '            ("run", "__none__"),',
    ),
    "gh ask: variable not folded in": (
        '            ("variable", "set"),\n            ("variable", "delete"),',
        '            ("variable", "__none__"),',
    ),
    "git ask: restore catches a named path too": (
        '        and "." in c.positionals()[1:]',
        "        and True",
    ),
    "git ask: restore --staged not spared": (
        '        and not (\n            "staged" in set(c.long_flags()) and "worktree" not in set(c.long_flags())\n        ),',
        "        and True,",
    ),
    "git ask: stash catches pop and list": (
        '        and bool({"drop", "clear"} & set(c.positionals()[1:3])),',
        "        and True,",
    ),
    "ask: decision ignored, everything denies": (
        '    if rule.decision == "ask":',
        "    if False:",
    ),
    "ask: every rule becomes an ask": (
        '    decision: str = "deny"',
        '    decision: str = "ask"',
    ),
    "ask: reason not carried through": (
        '                    "permissionDecisionReason": rule.message,',
        '                    "permissionDecisionReason": "",',
    ),
    "ask: git clean dry-run not spared": (
        '        and not (c.has_short_letter("n") or "dry-run" in set(c.long_flags())),',
        "        and True,",
    ),
    "background: flag never set": (
        '            command = normalize(current, background=token == "&")',
        "            command = normalize(current)",
    ),
    "background: && counts too": (
        '            command = normalize(current, background=token == "&")',
        '            command = normalize(current, background=token.startswith("&"))',
    ),
    "background: empty names match nothing": (
        "        if self.names and command.name not in self.names and command.program not in self.names:",
        "        if command.name not in self.names and command.program not in self.names:",
    ),
    "background: quoted & not shielded": (
        '    return QUOTED_AMPERSAND if char == "&" else char',
        "    return char",
    ),
    "background: spliced &) left whole": (
        "        result.extend(split_operators(token))",
        "        result.append(token)",
    ),
    "background: splitter breaks &> apart": (
        "        for width in range(min(3, len(token)), 0, -1):",
        "        for width in range(1, 2):",
    ),
    "detach: nohup back to a wrapper": (
        '        "nice",\n        "stdbuf",',
        '        "nice",\n        "nohup",\n        "setsid",\n        "stdbuf",',
    ),
    "detach: disown not covered": (
        '        names=frozenset({"nohup", "setsid", "disown"}),',
        '        names=frozenset({"nohup", "setsid"}),',
    ),
}


def run_suite(source: str) -> tuple[int, str]:
    with tempfile.TemporaryDirectory() as tmp:
        work = pathlib.Path(tmp)
        (work / GUARD).write_text(source)
        shutil.copy(HERE / TEST, work / TEST)
        proc = subprocess.run(
            [sys.executable, str(work / TEST)],
            capture_output=True,
            text=True,
            timeout=900,
        )
        return proc.returncode, proc.stdout


def main() -> int:
    code, out = run_suite(ORIGINAL)
    summary = out.strip().splitlines()[-1] if out.strip() else "<no output>"
    print(f"baseline: exit {code}  {summary}\n")
    if code != 0:
        print("baseline is already failing; fix the suite first")
        return 1

    stale: list[str] = []
    survivors: list[str] = []

    for label, (needle, replacement) in MUTATIONS.items():
        if needle not in ORIGINAL:
            print(f"STALE     {label}")
            stale.append(label)
            continue

        code, out = run_suite(ORIGINAL.replace(needle, replacement, 1))
        failed = [
            line.strip()[6:].strip()
            for line in out.splitlines()
            if line.startswith("FAIL  ")
        ]
        count = (re.search(r"fail=(\d+)", out) or [None, "?"])[1]

        if code != 0:
            print(f"CAUGHT    {label}  ({count} failed)")
            for name in failed[:2]:
                print(f"            - {name}")
        else:
            print(f"SURVIVED  {label}")
            survivors.append(label)

    print()
    if stale:
        print(f"{len(stale)} stale anchor(s), rewrite them: {', '.join(stale)}")
    if survivors:
        print(f"{len(survivors)} SURVIVED, add a test: {', '.join(survivors)}")
    if not stale and not survivors:
        print(f"all {len(MUTATIONS)} mutations caught")
    return 1 if (stale or survivors) else 0


if __name__ == "__main__":
    sys.exit(main())
