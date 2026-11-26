#!@python3@
from __future__ import annotations

import concurrent.futures
import os
import pathlib
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
        "    letters = INLINE_CODE_FLAG[command.program]",
        '    letters = "c" if command.program.startswith("python") else "e"',
    ),
    "interp: node -p not covered": (
        '    "node": "ep",',
        '    "node": "e",',
    ),
    "interp: perl -E not covered": (
        '    "perl": "eE",',
        '    "perl": "e",',
    ),
    "interp: long flags not read": (
        "    return any(command.has_trailing_short_flag(letter) for letter in letters) or bool(",
        "    return any(command.has_trailing_short_flag(letter) for letter in letters) and bool(",
    ),
    "push: --mirror not forced": (
        '            or any(flag.startswith("force") or flag == "mirror" for flag in c.long_flags())',
        '            or any(flag.startswith("force") for flag in c.long_flags())',
    ),
    "push: + refspec not forced": (
        '            or any(arg.startswith("+") and len(arg) > 1 for arg in c.positionals())',
        "            or False",
    ),
    "push: + inside a name counts": (
        '            or any(arg.startswith("+") and len(arg) > 1 for arg in c.positionals())',
        '            or any("+" in arg for arg in c.positionals())',
    ),
    "push: --prune not asked": (
        '            bool({"delete", "prune"} & set(c.long_flags()))',
        '            "delete" in set(c.long_flags())',
    ),
    "chmod: octal write bit not read": (
        "        return int(mode[-1]) & 2 == 2",
        '        return mode.endswith("777")',
    ),
    "chmod: symbolic modes not read": (
        '    for clause in mode.split(","):',
        "    for clause in []:",
    ),
    "chmod: only the first clause read": (
        '    for clause in mode.split(","):',
        '    for clause in mode.split(",")[:1]:',
    ),
    "chmod: removing w counts": (
        '        if match and set(match.group(1)) & {"o", "a"} and match.group(2) != "-":',
        '        if match and set(match.group(1)) & {"o", "a"}:',
    ),
    "chmod: nobody named counts as everyone": (
        '        if match and set(match.group(1)) & {"o", "a"} and match.group(2) != "-":',
        '        if match and (not match.group(1) or set(match.group(1)) & {"o", "a"}) and match.group(2) != "-":',
    ),
    "chmod: a not counted": (
        '        if match and set(match.group(1)) & {"o", "a"} and match.group(2) != "-":',
        '        if match and set(match.group(1)) & {"o"} and match.group(2) != "-":',
    ),
    "chmod: any permission counts": (
        '            if "w" in match.group(3):',
        "            if True:",
    ),
    "net: rule never matches": (
        "        predicate=lambda c: reaches_remote_host(c),",
        "        predicate=lambda c: False,",
    ),
    "net: openssl local connect denied": (
        "        return command.subcommand_is(\"s_client\") and target is not None and not is_local_host(target)",
        "        return command.subcommand_is(\"s_client\") and target is not None",
    ),
    "net: openssl any subcommand": (
        "        return command.subcommand_is(\"s_client\") and target is not None and not is_local_host(target)",
        "        return not command.subcommand_is(\"s_client\") or not is_local_host(target or \"\")",
    ),
    "net: socat listen counted": (
        '            if (match := SOCAT_ADDRESS.match(arg)) and "LISTEN" not in arg.upper()',
        "            if (match := SOCAT_ADDRESS.match(arg))",
    ),
    "net: socat not covered": (
        "        return any(not is_local_host(host) for host in hosts)\n    if name in SOCKET_TOOLS:",
        "        return False\n    if name in SOCKET_TOOLS:",
    ),
    "net: socket port read as host": (
        "        hosts = [word for word in words if not word.isdigit()]",
        "        hosts = list(words)",
    ),
    "net: socket value flag read as host": (
        "        words = positional_words(command, SOCKET_VALUE_FLAGS)",
        "        words = positional_words(command, frozenset())",
    ),
    "net: http method read as target": (
        "    targets = [arg for arg in command.positionals() if arg.upper() not in HTTP_METHODS]",
        "    targets = list(command.positionals())",
    ),
    "net: httpie :port not local": (
        '    return not (target.startswith(":") or is_local_host(target))',
        "    return not is_local_host(target)",
    ),
    "net: local host denied": (
        '    return not (target.startswith(":") or is_local_host(target))',
        "    return True",
    ),
    "service: info flags not exempt": (
        "    if command.only_prints_info():\n        return False\n    if name == \"coproc\":",
        "    if name == \"coproc\":",
    ),
    "service: coproc not covered": (
        '    if name == "coproc":\n        return True',
        '    if name == "coproc":\n        return False',
    ),
    "service: at -l not exempt": (
        '        return not command.has_short_letter("lrc")',
        "        return True",
    ),
    "service: at not covered": (
        '        return not command.has_short_letter("lrc")',
        "        return False",
    ),
    "service: launchctl any subcommand": (
        "        return command.subcommand_is(*LAUNCHD_STARTS)",
        "        return True",
    ),
    "service: launchctl not covered": (
        "        return command.subcommand_is(*LAUNCHD_STARTS)",
        "        return False",
    ),
    "service: screen -m alone counts": (
        '        return command.has_short_letter("d") and command.has_short_letter("m")',
        '        return command.has_short_letter("m")',
    ),
    "service: screen -d alone counts": (
        '        return command.has_short_letter("d") and command.has_short_letter("m")',
        '        return command.has_short_letter("d")',
    ),
    "service: tmux detach flag ignored": (
        "    return bool(flag) and command.has_short_letter(flag)",
        "    return bool(flag)",
    ),
    "service: tmux not covered": (
        "    return bool(flag) and command.has_short_letter(flag)",
        "    return False",
    ),
    "service: tmux global value flag read as subcommand": (
        "    words = positional_words(command, TMUX_VALUE_FLAGS)",
        "    words = positional_words(command, frozenset())",
    ),
    "service: tmux run-shell -b not covered": (
        '    "run-shell": "b",',
        '    "run-shell": "",',
    ),
    "interp: flags after the script read": (
        "    own = command.args[:script]",
        "    own = command.args",
    ),
    "interp: long flag value not split off": (
        '    long_flags = {arg[2:].split("=", 1)[0] for arg in own if arg.startswith("--")}',
        '    long_flags = {arg[2:] for arg in own if arg.startswith("--")}',
    ),
    "interp: node --print not covered": (
        '    "node": frozenset({"eval", "print"}),',
        '    "node": frozenset({"eval"}),',
    ),
    "interp: bun --eval not covered": (
        '    "bun": frozenset({"eval", "print"}),',
        '    "bun": frozenset({"print"}),',
    ),
    "interp: deno eval not covered": (
        '    if command.program == "deno":\n        return command.subcommand_is("eval")',
        '    if command.program == "deno":\n        return False',
    ),
    "awk: system() not seen": (
        r'AWK_RUNS_COMMAND = re.compile(r"system\s*\(|\|\s*\"|\"\s*\|\s*getline|\|&")',
        r'AWK_RUNS_COMMAND = re.compile(r"\|\s*\"|\"\s*\|\s*getline|\|&")',
    ),
    "awk: print | cmd not seen": (
        r'AWK_RUNS_COMMAND = re.compile(r"system\s*\(|\|\s*\"|\"\s*\|\s*getline|\|&")',
        r'AWK_RUNS_COMMAND = re.compile(r"system\s*\(|\"\s*\|\s*getline|\|&")',
    ),
    "awk: cmd | getline not seen": (
        r'AWK_RUNS_COMMAND = re.compile(r"system\s*\(|\|\s*\"|\"\s*\|\s*getline|\|&")',
        r'AWK_RUNS_COMMAND = re.compile(r"system\s*\(|\|\s*\"|\|&")',
    ),
    "awk: coprocess not seen": (
        r'AWK_RUNS_COMMAND = re.compile(r"system\s*\(|\|\s*\"|\"\s*\|\s*getline|\|&")',
        r'AWK_RUNS_COMMAND = re.compile(r"system\s*\(|\|\s*\"|\"\s*\|\s*getline")',
    ),
    "sed: e command not seen": (
        "        SED_E_COMMAND.search(script) or SED_S_E_FLAG.search(script)",
        "        SED_S_E_FLAG.search(script)",
    ),
    "sed: s///e not seen": (
        "        SED_E_COMMAND.search(script) or SED_S_E_FLAG.search(script)",
        "        SED_E_COMMAND.search(script)",
    ),
    "sed: -e scripts not read": (
        '        if arg in {"-e", "--expression"} and index + 1 < len(args):',
        "        if False:",
    ),
    "sed: --expression= not read": (
        '        elif arg.startswith("--expression="):',
        "        elif False:",
    ),
    "sed: operand script not read": (
        "        scripts = positionals[:1]",
        "        scripts = []",
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
        '            and tokens[0] == "nix"\n            and marker is not None',
        '            and False\n            and marker is not None',
    ),
    "nix: -c not stripped": (
        '            (i for i, token in enumerate(tokens) if token in {"--command", "-c"}), None',
        '            (i for i, token in enumerate(tokens) if token == "--command"), None',
    ),
    "relay: nix-shell --run not unpacked": (
        '        return flag_value(command, "--run") or flag_value(command, "--command")',
        '        return flag_value(command, "--command")',
    ),
    "relay: nix-shell --command not unpacked": (
        '        return flag_value(command, "--run") or flag_value(command, "--command")',
        '        return flag_value(command, "--run")',
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
        '    if rule.decision in {"ask", "allow"}:',
        "    if False:",
    ),
    "allow: falls back to the ask branch": (
        '    if rule.decision in {"ask", "allow"}:',
        '    if rule.decision == "ask":',
    ),
    "allow: decision hard-coded to ask": (
        '                    "permissionDecision": rule.decision,',
        '                    "permissionDecision": "ask",',
    ),
    "allow: one matching sub-command is enough": (
        "    if matches and all(\n        rule and rule.decision == \"allow\" and not command.prefixed",
        "    if matches and any(\n        rule and rule.decision == \"allow\" and not command.prefixed",
    ),
    "allow: malformed line still allowed": (
        "    if malformed:\n        return fallback_ask(matches)",
        "    if False:\n        return fallback_ask(matches)",
    ),
    "allow: no fallback to the ask behind it": (
        "            if ask:\n                return ask, command",
        "            if False:\n                return ask, command",
    ),
    "allow: fallback reaches for another allow": (
        '            ask = next((r for r in RULES if r.decision == "ask" and r.matches(command)), None)',
        "            ask = next((r for r in RULES if r.matches(command)), None)",
    ),
    "allow: malformed flag never set": (
        "        malformed = True\n        rough = re.sub(",
        "        rough = re.sub(",
    ),
    "allow: prefix ignored": (
        '        rule and rule.decision == "allow" and not command.prefixed',
        '        rule and rule.decision == "allow"',
    ),
    "allow: path prefix not counted": (
        "        prefixed=len(tokens) != original_length or name != tokens[0],",
        "        prefixed=len(tokens) != original_length,",
    ),
    "allow: wrapper prefix not counted": (
        "        prefixed=len(tokens) != original_length or name != tokens[0],",
        "        prefixed=name != tokens[0],",
    ),
    "allow: ask no longer outranks it": (
        '    for decision in ("deny", "ask"):',
        '    for decision in ("deny",):',
    ),
    "allow: deny no longer outranks ask": (
        '    for decision in ("deny", "ask"):',
        '    for decision in ("ask", "deny"):',
    ),
    "allow: nested shell -c not folded in": (
        "                inner, inner_malformed = match_all(payload, depth + 1)",
        "                inner, inner_malformed = [], False",
    ),
    "checkout: -B let through": (
        '        "-b",\n        "--orphan",',
        '        "-b",\n        "-B",\n        "--orphan",',
    ),
    "checkout: -- let through": (
        '        "--no-progress",\n    }',
        '        "--no-progress",\n        "--",\n    }',
    ),
    "checkout: any flag accepted": (
        "    if any(flag not in CHECKOUT_BRANCH_FLAGS for flag in flags):\n        return False",
        "    if False:\n        return False",
    ),
    "checkout: plain switch let through": (
        '    if not {"-b", "--orphan"} & set(rest):\n        return False',
        "    if False:\n        return False",
    ),
    "checkout: extra positionals accepted": (
        "    return 1 <= len(names) <= 2 and all(REF_NAME.match(name) for name in names)",
        "    return 1 <= len(names) and all(REF_NAME.match(name) for name in names)",
    ),
    "checkout: bare -b accepted": (
        "    return 1 <= len(names) <= 2 and all(REF_NAME.match(name) for name in names)",
        "    return len(names) <= 2 and all(REF_NAME.match(name) for name in names)",
    ),
    "checkout: names not vetted": (
        "    return 1 <= len(names) <= 2 and all(REF_NAME.match(name) for name in names)",
        "    return 1 <= len(names) <= 2",
    ),
    "checkout: name may start with a dot": (
        'REF_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/@^~+-]*$")',
        'REF_NAME = re.compile(r"^[A-Za-z0-9._/@^~+-]+$")',
    ),
    "checkout: shell metacharacters in a name": (
        'REF_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/@^~+-]*$")',
        'REF_NAME = re.compile(r"^[A-Za-z0-9][^ ]*$")',
    ),
    "rebase: --skip let through": (
        '        predicate=lambda c: c.args in {("rebase", "--abort"), ("rebase", "--continue")},',
        '        predicate=lambda c: c.args in {("rebase", "--abort"), ("rebase", "--continue"), ("rebase", "--skip")},',
    ),
    "rebase: extra args accepted": (
        '        predicate=lambda c: c.args in {("rebase", "--abort"), ("rebase", "--continue")},',
        '        predicate=lambda c: c.args[:2] in {("rebase", "--abort"), ("rebase", "--continue")},',
    ),
    "checkout: global git flag accepted": (
        '    if not command.args or command.args[0] != "checkout":',
        '    if not command.subcommand_is("checkout"):',
    ),
    "git ask: commit not covered": (
        '        predicate=lambda c: git_subcommand(c) == "commit",',
        '        predicate=lambda c: git_subcommand(c) == "__none__",',
    ),
    "git ask: push not covered": (
        '        predicate=lambda c: git_subcommand(c) == "push",',
        '        predicate=lambda c: git_subcommand(c) == "__none__",',
    ),
    "git ask: rebase not covered": (
        '        predicate=lambda c: git_subcommand(c) == "rebase",',
        '        predicate=lambda c: git_subcommand(c) == "__none__",',
    ),
    "git ask: checkout not covered": (
        '        predicate=lambda c: git_subcommand(c) == "checkout",',
        '        predicate=lambda c: git_subcommand(c) == "__none__",',
    ),
    "git ask: any of the first two words counts": (
        '        predicate=lambda c: git_subcommand(c) == "push",',
        '        predicate=lambda c: c.subcommand_is("push"),',
    ),
    "git ask: global flag values read as the subcommand": (
        '    {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"}',
        "    set()",
    ),
    "git ask: global flags not skipped at all": (
        '        elif not arg.startswith("-"):\n            return arg',
        "        else:\n            return arg",
    ),
    "git ask: broad ask listed ahead of the allows": (
        '    Rule(\n        id="git-checkout-branch",',
        "    Rule(\n"
        '        id="git-checkout-early",\n'
        '        names=frozenset({"git"}),\n'
        '        decision="ask",\n'
        '        predicate=lambda c: git_subcommand(c) == "checkout",\n'
        '        message="early",\n'
        "    ),\n"
        '    Rule(\n        id="git-checkout-branch",',
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
        '            command = normalize(current, background=token == "&", substituted=substituted)',
        "            command = normalize(current, substituted=substituted)",
    ),
    "background: && counts too": (
        '            command = normalize(current, background=token == "&", substituted=substituted)',
        '            command = normalize(\n                current, background=token.startswith("&"), substituted=substituted\n            )',
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
        '        "nice",\n        "script",',
        '        "nice",\n        "nohup",\n        "script",\n        "setsid",',
    ),
    "detach: disown not covered": (
        '        names=frozenset({"nohup", "setsid", "disown"}),',
        '        names=frozenset({"nohup", "setsid"}),',
    ),
    "op: substitution not shielded": (
        "    if command.substituted:\n        return False",
        "    if False:\n        return False",
    ),
    "op: every ( counts as a substitution": (
        '            substituted = token == "(" and bool(current) and current[-1].endswith("$")',
        '            substituted = token == "("',
    ),
    "op: substitution outlives its first command": (
        '            substituted = token == "(" and bool(current) and current[-1].endswith("$")',
        '            substituted = substituted or (\n                token == "(" and bool(current) and current[-1].endswith("$")\n            )',
    ),
    "op: global flag value read as subcommand": (
        '        elif arg in OP_VALUE_FLAGS:\n            skip = True\n        elif not arg.startswith("-"):\n            words.append(arg)\n    return tuple(words)\n\n\nSOCKET_TOOLS',
        '        elif not arg.startswith("-"):\n            words.append(arg)\n    return tuple(words)\n\n\nSOCKET_TOOLS',
    ),
    "op: help not exempt": (
        '    if "help" in set(command.long_flags()) or "-h" in command.args:\n        return False\n\n    words = op_words',
        "    words = op_words",
    ),
    "op: read not covered": (
        '    if words[:1] == ("read",):\n        return True',
        '    if words[:1] == ("read",):\n        return False',
    ),
    "op: inject out-file not exempt": (
        '    if words[:1] == ("inject",):\n        return not writes_file',
        '    if words[:1] == ("inject",):\n        return True',
    ),
    "op: inject not covered": (
        '    if words[:1] == ("inject",):\n        return not writes_file',
        '    if words[:1] == ("inject",):\n        return False',
    ),
    "op: document get not covered": (
        '    if words[:2] == ("document", "get"):\n        return not writes_file',
        '    if words[:2] == ("document", "get"):\n        return False',
    ),
    "op: -o not read as out-file": (
        '    out = flag_value(command, "--out-file") or flag_value(command, "-o")',
        '    out = flag_value(command, "--out-file")',
    ),
    "op: stdout as out-file not seen": (
        "    writes_file = out is not None and not STDOUT_PATH.match(out)",
        "    writes_file = out is not None",
    ),
    "op: /dev/fd not seen": (
        r'STDOUT_PATH = re.compile(r"^(?:-|/dev/(?:stdout|stderr|tty|fd/[0-9]+)|/proc/self/fd/[0-9]+)$")',
        r'STDOUT_PATH = re.compile(r"^(?:-|/dev/(?:stdout|stderr|tty)|/proc/self/fd/[0-9]+)$")',
    ),
    "op: share link not covered": (
        '    if words[:2] == ("item", "get") and "share-link" in long_flags:\n        return True',
        '    if False:\n        return True',
    ),
    "op: reveal not covered": (
        '        return bool(long_flags & {"reveal", "fields", "otp"}) or (',
        '        return bool(long_flags & {"fields", "otp"}) or (',
    ),
    "op: fields not covered": (
        '        return bool(long_flags & {"reveal", "fields", "otp"}) or (',
        '        return bool(long_flags & {"reveal", "otp"}) or (',
    ),
    "op: otp not covered": (
        '        return bool(long_flags & {"reveal", "fields", "otp"}) or (',
        '        return bool(long_flags & {"reveal", "fields"}) or (',
    ),
    "op: format json case-sensitive": (
        '            (flag_value(command, "--format") or "").lower() == "json"',
        '            (flag_value(command, "--format") or "") == "json"',
    ),
    "fetch: info exemption dropped": (
        "        predicate=lambda c: not c.targets_only_localhost()\n        and not c.only_prints_info(FETCH_INFO_FLAGS),",
        "        predicate=lambda c: not c.targets_only_localhost(),",
    ),
    "fetch: manual flags not exempt": (
        'FETCH_INFO_FLAGS = INFO_FLAGS | {"--manual", "-M"}',
        "FETCH_INFO_FLAGS = INFO_FLAGS",
    ),
    "info: any one flag exempts": (
        "        return bool(self.args) and all(arg in flags for arg in self.args)",
        "        return any(arg in flags for arg in self.args)",
    ),
    "info: bare command exempt": (
        "        return bool(self.args) and all(arg in flags for arg in self.args)",
        "        return all(arg in flags for arg in self.args)",
    ),
    "info: detach not exempt": (
        '        predicate=lambda c: c.name == "disown" or not c.only_prints_info(),',
        "        predicate=lambda c: True,",
    ),
    "info: disown -h exempt": (
        '        predicate=lambda c: c.name == "disown" or not c.only_prints_info(),',
        "        predicate=lambda c: not c.only_prints_info(),",
    ),
    "info: runner not exempt": (
        "        names=RUNNER_COMMANDS,\n        predicate=lambda c: not c.only_prints_info(),",
        "        names=RUNNER_COMMANDS,",
    ),
    "relay: not unpacked": (
        "            payload = nested_command(command) or relayed_command(command)",
        "            payload = nested_command(command)",
    ),
    "relay: ssh value flag not skipped": (
        "        elif arg in SSH_VALUE_FLAGS:\n            skip = True",
        "        elif False:\n            skip = True",
    ),
    "relay: ssh -- read as destination": (
        '        elif arg == "--":\n            continue',
        '        elif arg == "--":\n            return None',
    ),
    "relay: ssh destination kept in payload": (
        "            rest = args[index + 1 :]",
        "            rest = args[index:]",
    ),
    "relay: ssh not covered": (
        '    if name == "ssh":\n        return remote_command(args)',
        '    if name == "ssh":\n        return None',
    ),
    "relay: tailscale ssh not covered": (
        '    if name == "tailscale" and args[:1] == ("ssh",):',
        "    if False:",
    ),
    "relay: name case kept": (
        "    name = command.program.lower()",
        "    name = command.program",
    ),
    "relay: k3s kubectl not covered": (
        '    if name == "k3s" and args[:1] == ("kubectl",):',
        "    if False:",
    ),
    "relay: kubectl any subcommand": (
        '    if name in {"kubectl", "oc"} and "exec" in head:',
        '    if name in {"kubectl", "oc"}:',
    ),
    "relay: kubectl exec after --": (
        '    head = args[: args.index("--")] if "--" in args else args',
        "    head = args",
    ),
    "relay: oc not covered": (
        '    if name in {"kubectl", "oc"} and "exec" in head:',
        '    if name == "kubectl" and "exec" in head:',
    ),
    "relay: mise any subcommand": (
        '    if name in MISE_NAMES and mise_subcommand(command) in {"exec", "x"}:',
        "    if name in MISE_NAMES:",
    ),
    "relay: mise -c not unpacked": (
        '        inline = flag_value(command, "--command") or flag_value(command, "-c")',
        "        inline = None",
    ),
    "relay: rtx not covered": (
        '    if name in MISE_NAMES and mise_subcommand(command) in {"exec", "x"}:',
        '    if name == "mise" and mise_subcommand(command) in {"exec", "x"}:',
    ),
    "mise: x not denied": (
        '        predicate=lambda c: mise_subcommand(c) == "x",',
        "        predicate=lambda c: False,",
    ),
    "mise: exec tool spec allowed": (
        "        elif not arg.startswith(\"-\"):\n            return True\n    return False",
        "        elif not arg.startswith(\"-\"):\n            return False\n    return False",
    ),
    "nix: remote prefix stripped": (
        "            and not nix_fetches(tokens[1:])",
        "            and True",
    ),
    "nix: -c not an end marker": (
        '        (i for i, arg in enumerate(args) if arg in {"--command", "-c", "--"}), len(args)',
        '        (i for i, arg in enumerate(args) if arg in {"--command", "--"}), len(args)',
    ),
    "go: remote run allowed": (
        '        and "@" in words[1]',
        '        and "@" in words[0]',
    ),
    "uv: --with allowed": (
        '    if any(arg == "--with" or arg.startswith("--with=") for arg in own):',
        "    if False:",
    ),
    "deno: bare remote allowed": (
        '    if words[:1] == ("run",):\n        words = words[1:]',
        '    if words[:1] != ("run",):\n        return False\n    words = words[1:]',
    ),
    "relay: runner args not requoted": (
        "    return shlex.join(rest) if rest else None",
        '    return " ".join(rest) if rest else None',
    ),
    "wrapper: path not stripped": (
        '        wrapper = tokens[0].rsplit("/", 1)[-1] if tokens else ""',
        '        wrapper = tokens[0] if tokens else ""',
    ),
    "wrapper: own positionals kept": (
        "            del tokens[: WRAPPER_POSITIONALS.get(wrapper, 0)]",
        "            pass",
    ),
    "wrapper: arch value flag not skipped": (
        '    "arch": frozenset({"-arch"}),',
        '    "arch": frozenset(),',
    ),
    "wrapper: flock value flag not skipped": (
        '    "flock": frozenset({"-w", "--wait", "--timeout", "-E", "--conflict-exit-code"}),',
        '    "flock": frozenset(),',
    ),
    "wrapper: script value flag not skipped": (
        '    "script": frozenset({"-F", "-t", "-T"}),',
        '    "script": frozenset(),',
    ),
    "relay: watch not unpacked": (
        '    if name == "watch":\n        index',
        '    if False:\n        index',
    ),
    "relay: watch value flag not skipped": (
        '        index = past_options(args, frozenset({"-n", "--interval"}))',
        "        index = past_options(args, frozenset())",
    ),
    "relay: find -exec not unpacked": (
        '    if name == "find":',
        "    if False:",
    ),
    "relay: find -ok not covered": (
        'FIND_EXEC_FLAGS = frozenset({"-exec", "-execdir", "-ok", "-okdir"})',
        'FIND_EXEC_FLAGS = frozenset({"-exec", "-execdir"})',
    ),
    "relay: find -execdir not covered": (
        'FIND_EXEC_FLAGS = frozenset({"-exec", "-execdir", "-ok", "-okdir"})',
        'FIND_EXEC_FLAGS = frozenset({"-exec", "-ok", "-okdir"})',
    ),
    "relay: container exec not unpacked": (
        '        if args[:1] in {("exec",), ("run",)}:',
        "        if False:",
    ),
    "relay: container run not covered": (
        '        if args[:1] in {("exec",), ("run",)}:',
        '        if args[:1] == ("exec",):',
    ),
    "relay: compose not covered": (
        '        if args[:2] in {("compose", "exec"), ("compose", "run")}:\n            args = args[1:]',
        '        if False:\n            args = args[1:]',
    ),
    "relay: container value flags not skipped": (
        "            return after_target(args[1:], CONTAINER_VALUE_FLAGS)",
        "            return after_target(args[1:], frozenset())",
    ),
    "relay: container image kept in payload": (
        "    rest = args[index + 1 :] if index is not None else ()",
        "    rest = args[index:] if index is not None else ()",
    ),
    "relay: limactl not unpacked": (
        '    if name == "limactl" and args[:1] == ("shell",):',
        "    if False:",
    ),
    "relay: podman not covered": (
        'CONTAINER_TOOLS = frozenset({"docker", "podman", "nerdctl", "container"})',
        'CONTAINER_TOOLS = frozenset({"docker", "nerdctl", "container"})',
    ),
    "relay: apple container not covered": (
        'CONTAINER_TOOLS = frozenset({"docker", "podman", "nerdctl", "container"})',
        'CONTAINER_TOOLS = frozenset({"docker", "podman", "nerdctl"})',
    ),
    "relay: target args not requoted": (
        "    return shlex.join(rest) if rest else None\n\n\ndef after_double_dash",
        '    return " ".join(rest) if rest else None\n\n\ndef after_double_dash',
    ),
    "shell-stdin: -c not exempt": (
        "    if nested_command(command) is not None:\n        return False\n    if \"-\" in command.args",
        "    if \"-\" in command.args",
    ),
    "shell-stdin: heredoc not counted": (
        '    if "-" in command.args or set(command.args) & {"<<", "<<-", "<<<"}:',
        '    if "-" in command.args:',
    ),
    "shell-stdin: dash not counted": (
        '    if "-" in command.args or set(command.args) & {"<<", "<<-", "<<<"}:',
        '    if set(command.args) & {"<<", "<<-", "<<<"}:',
    ),
    "shell-stdin: pipe not counted": (
        '    return command.piped and (command.has_short_letter("s") or not command.positionals())',
        "    return False",
    ),
    "shell-stdin: pipe with a script file counted": (
        '    return command.piped and (command.has_short_letter("s") or not command.positionals())',
        "    return command.piped",
    ),
    "shell-stdin: -s with args ignored": (
        '    return command.piped and (command.has_short_letter("s") or not command.positionals())',
        "    return command.piped and not command.positionals()",
    ),
    "piped: never set": (
        '            piped = token in {"|", "|&"}',
        "            piped = False",
    ),
    "piped: |& not counted": (
        '            piped = token in {"|", "|&"}',
        '            piped = token == "|"',
    ),
    "piped: any separator counts": (
        '            piped = token in {"|", "|&"}',
        "            piped = True",
    ),
    "eval: not unpacked": (
        '    if name == "eval":\n        return " ".join(args) or None',
        '    if name == "eval":\n        return None',
    ),
    "variable: not asked": (
        '        predicate=lambda c: c.name.startswith("$"),',
        "        predicate=lambda c: False,",
    ),
    "dquote: $( left inside the string": (
        """        if quote == '"' and command_line.startswith("$(", index):""",
        "        if False:",
    ),
    "dquote: backtick left inside the string": (
        """        if quote == '"' and char == "`":""",
        "        if False:",
    ),
    "dquote: string not reopened after )": (
        '        if char == ")" and reopen and reopen[-1] == depth:',
        "        if False:",
    ),
    "dquote: string not reopened after backtick": (
        '        if char == "`" and backtick_reopens:',
        "        if False:",
    ),
    "dquote: nested parens not counted": (
        '        if char == "(":\n            depth += 1',
        '        if char == "(":\n            pass',
    ),
    "heredoc: not detected": (
        '        heredoc = HEREDOC.match(command_line, index) if char == "<" else None',
        "        heredoc = None",
    ),
    "heredoc: inert body kept": (
        '            if not inert:\n                result.append(line + "\\n")',
        '            result.append(line + "\\n")',
    ),
    "heredoc: live body dropped": (
        '            if not inert:\n                result.append(line + "\\n")',
        '            if False:\n                result.append(line + "\\n")',
    ),
    "heredoc: consumer not checked": (
        '            inert = bool(heredoc.group("quoted")) and heredoc_consumer(result) in HEREDOC_TEXT_SINKS',
        '            inert = bool(heredoc.group("quoted"))',
    ),
    "heredoc: pipe after operator ignored": (
        '                (word, tabs, inert and "|" not in command_line[op_end:index])',
        "                (word, tabs, inert)",
    ),
    "heredoc: consumer path kept": (
        '            return word.rsplit("/", 1)[-1]',
        "            return word",
    ),
    "heredoc: assignment read as consumer": (
        "        if not ASSIGNMENT.match(word):\n            return word.rsplit",
        "        if True:\n            return word.rsplit",
    ),
    "heredoc: consumer from line start": (
        '    start = max(text.rfind(sep) for sep in ";|&(\\n") + 1',
        "    start = 0",
    ),
    "heredoc: tabs never stripped": (
        '(line.lstrip("\\t") if strip_tabs else line)',
        "line",
    ),
    "heredoc: tabs always stripped": (
        '(line.lstrip("\\t") if strip_tabs else line)',
        'line.lstrip("\\t")',
    ),
    "heredoc: here-string read as heredoc": (
        'r"(?<!<)<<(?!<)',
        'r"<<',
    ),
    "heredoc: only the first body skipped": (
        "    for delimiter, strip_tabs, inert in pending:",
        "    for delimiter, strip_tabs, inert in pending[:1]:",
    ),
    "heredoc: backslash delimiter not quoting": (
        r"""(?P<quoted>['\"\\])?""",
        r"""(?P<quoted>['\"])?""",
    ),
    "fallback: redirect & split out": (
        "(?<![<>])&(?!>)",
        "&",
    ),
    "op: any format counts": (
        '            (flag_value(command, "--format") or "").lower() == "json"',
        '            flag_value(command, "--format") is not None',
    ),
}


MUTANT_TIMEOUT = 60


def run_suite(source: str, fail_fast: bool = True) -> tuple[int | None, str]:
    env = {**os.environ, "PYTHONHASHSEED": "0", "GUARD_SUBPROCESS": "", "GUARD_BIN": ""}
    if fail_fast:
        env["GUARD_FAIL_FAST"] = "1"
    with tempfile.TemporaryDirectory() as tmp:
        work = pathlib.Path(tmp)
        (work / GUARD).write_text(source)
        shutil.copy(HERE / TEST, work / TEST)
        try:
            proc = subprocess.run(
                [sys.executable, str(work / TEST)],
                capture_output=True,
                text=True,
                timeout=MUTANT_TIMEOUT,
                env=env,
            )
        except subprocess.TimeoutExpired:
            return None, ""
        return proc.returncode, proc.stdout


def main() -> int:
    code, out = run_suite(ORIGINAL, fail_fast=False)
    summary = out.strip().splitlines()[-1] if out.strip() else "<no output>"
    print(f"baseline: exit {code}  {summary}\n")
    if code != 0:
        print("baseline is already failing; fix the suite first")
        return 1

    stale = [label for label, (needle, _) in MUTATIONS.items() if needle not in ORIGINAL]
    live = {label: pair for label, pair in MUTATIONS.items() if label not in stale}
    with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
        results = dict(
            zip(
                live,
                pool.map(
                    lambda pair: run_suite(ORIGINAL.replace(pair[0], pair[1], 1)),
                    live.values(),
                ),
            )
        )

    survivors: list[str] = []
    for label in MUTATIONS:
        if label in stale:
            print(f"STALE     {label}")
            continue
        code, out = results[label]
        if code is None:
            print(f"TIMEOUT   {label}  (killed after {MUTANT_TIMEOUT}s, counted as caught)")
        elif code != 0:
            first = next(
                (line.strip()[6:].strip() for line in out.splitlines() if line.startswith("FAIL  ")),
                "",
            )
            print(f"CAUGHT    {label}")
            print(f"            - {first}")
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
