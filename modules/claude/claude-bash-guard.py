#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import shlex
import sys
from dataclasses import dataclass, field, replace
from typing import Callable, Iterator, Sequence

SEPARATORS = frozenset({"&&", "||", ";", ";;", "|", "|&", "&", "(", ")", "{", "}"})

KEYWORDS = frozenset({"then", "else", "elif", "do", "done", "fi", "esac", "!"})

REDIRECTS = frozenset({"<", "<<", "<<<", "<<-", "<&", "<>", ">", ">>", ">&", ">|", "&>", "&>>"})
OPERATORS = SEPARATORS | REDIRECTS
PUNCTUATION = frozenset("();<>|&")

QUOTED_AMPERSAND = "\x00amp\x00"

WRAPPERS = frozenset(
    {
        "arch",
        "builtin",
        "caffeinate",
        "command",
        "doas",
        "env",
        "exec",
        "flock",
        "nice",
        "script",
        "stdbuf",
        "sudo",
        "time",
        "timeout",
        "xargs",
    }
)

WRAPPER_POSITIONALS: dict[str, int] = {"flock": 1, "script": 1}

WRAPPER_VALUE_FLAGS: dict[str, frozenset[str]] = {
    "arch": frozenset({"-arch"}),
    "doas": frozenset({"-u", "-C"}),
    "flock": frozenset({"-w", "--wait", "--timeout", "-E", "--conflict-exit-code"}),
    "script": frozenset({"-F", "-t", "-T"}),
    "env": frozenset({"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}),
    "nice": frozenset({"-n", "--adjustment"}),
    "stdbuf": frozenset({"-i", "-o", "-e", "--input", "--output", "--error"}),
    "sudo": frozenset({"-u", "-g", "-U", "-C", "-p", "-r", "-t"}),
    "timeout": frozenset({"-s", "--signal", "-k", "--kill-after"}),
    "xargs": frozenset({"-I", "-n", "-P", "-s", "-L", "-E", "-d", "-a"}),
}

STDIN_REDIRECTS = frozenset({"<", "<<", "<<<", "<<-"})

SHELLS = frozenset({"bash", "sh", "zsh", "dash", "ksh", "fish"})

ECHO_LIMIT = 200

ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

HEREDOC = re.compile(
    r"(?<!<)<<(?!<)(?P<tabs>-?)[ \t]*(?P<quoted>['\"\\])?(?P<word>[A-Za-z0-9_.\-]+)['\"]?"
)
VERSION_SUFFIX = re.compile(r"[0-9.]+$")
DURATION = re.compile(r"^[0-9]+[smhd]?$")
OCTAL_MODE = re.compile(r"^[0-7]{3,4}$")
SYMBOLIC_CLAUSE = re.compile(r"^([ugoa]*)([-+=])([rwxXst]*)$")


def world_writable(mode: str) -> bool:
    if OCTAL_MODE.match(mode):
        return int(mode[-1]) & 2 == 2
    for clause in mode.split(","):
        match = SYMBOLIC_CLAUSE.match(clause)
        if match and set(match.group(1)) & {"o", "a"} and match.group(2) != "-":
            if "w" in match.group(3):
                return True
    return False

LOCAL_TARGET = re.compile(
    r"^(?:[a-z][a-z0-9+.\-]*://)?"
    r"(?:\[::1\]|::1|localhost|127(?:\.[0-9]{1,3}){3}|0\.0\.0\.0)"
    r"(?::[^/?#@]*)?(?:[/?#]|$)",
    re.IGNORECASE,
)

INFO_FLAGS = frozenset({"--version", "-V", "--help", "-h"})

FETCH_INFO_FLAGS = INFO_FLAGS | {"--manual", "-M"}


@dataclass(frozen=True)
class Command:
    name: str
    args: tuple[str, ...]
    raw: str
    background: bool = False
    prefixed: bool = False
    substituted: bool = False
    piped: bool = False

    @property
    def program(self) -> str:
        return VERSION_SUFFIX.sub("", self.name) or self.name

    def short_flag_clusters(self) -> Iterator[str]:
        for arg in self.args:
            if arg.startswith("-") and not arg.startswith("--") and len(arg) > 1:
                yield arg[1:].split(".", 1)[0]

    def long_flags(self) -> Iterator[str]:
        for arg in self.args:
            if arg.startswith("--") and len(arg) > 2:
                yield arg[2:].split("=", 1)[0]

    def has_short_letter(self, letters: str) -> bool:
        return any(set(cluster) & set(letters) for cluster in self.short_flag_clusters())

    def has_trailing_short_flag(self, letter: str) -> bool:
        return any(cluster.endswith(letter) for cluster in self.short_flag_clusters())

    def edits_in_place(self) -> bool:
        return self.has_trailing_short_flag("i") or "in-place" in set(self.long_flags())

    def positionals(self) -> list[str]:
        return [arg for arg in self.args if not arg.startswith("-")]

    def subcommand_is(self, *names: str) -> bool:
        return bool(set(self.positionals()[:2]) & set(names))

    def reads_stdin_script(self) -> bool:
        return "-" in self.args or bool(set(self.args) & STDIN_REDIRECTS)

    def fetch_targets(self) -> list[str]:
        return [
            arg
            for arg in self.args
            if not arg.startswith("-") and ("://" in arg or LOCAL_TARGET.match(arg))
        ]

    def only_prints_info(self, flags: frozenset[str] = INFO_FLAGS) -> bool:
        return bool(self.args) and all(arg in flags for arg in self.args)

    def targets_only_localhost(self) -> bool:
        targets = self.fetch_targets()
        return bool(targets) and all(LOCAL_TARGET.match(target) for target in targets)


@dataclass(frozen=True)
class Rule:
    id: str
    names: frozenset[str]
    message: str
    predicate: Callable[[Command], bool] = field(default=lambda _: True)
    decision: str = "deny"

    def matches(self, command: Command) -> bool:
        if self.names and command.name not in self.names and command.program not in self.names:
            return False
        return self.predicate(command)


RUNNER_COMMANDS = frozenset(
    {"npx", "pnpx", "pnx", "bunx", "uvx", "dnx", "jbang", "pkgx", ",", "comma", "cgx",
     "pip-run", "dx"}
)

RUNNER_SUBCOMMANDS: dict[str, frozenset[str]] = {
    "npm": frozenset({"exec", "x", "create"}),
    "pnpm": frozenset({"dlx", "create"}),
    "yarn": frozenset({"dlx", "create"}),
    "bun": frozenset({"x", "create"}),
    "pipx": frozenset({"run", "install"}),
    "gem": frozenset({"exec"}),
    "dotnet": frozenset({"dnx"}),
    "corepack": frozenset(
        {"npm", "npx", "pnpm", "pnpx", "yarn", "yarnpkg", "install", "use", "up"}
    ),
}

RUNNER_SUBCOMMAND_PAIRS: dict[str, frozenset[tuple[str, str]]] = {
    "uv": frozenset({("tool", "run"), ("tool", "install")}),
    "dotnet": frozenset({("tool", "exec")}),
}

INLINE_CODE_FLAG: dict[str, str] = {
    "python": "c",
    "node": "ep",
    "ruby": "e",
    "perl": "eE",
    "swift": "e",
    "bun": "e",
    "osascript": "e",
    "php": "r",
}

INLINE_CODE_LONG: dict[str, frozenset[str]] = {
    "node": frozenset({"eval", "print"}),
    "bun": frozenset({"eval", "print"}),
}

INTERPRETERS = frozenset(INLINE_CODE_FLAG)


def runs_inline_code(command: Command) -> bool:
    if command.program == "deno":
        return command.subcommand_is("eval")
    letters = INLINE_CODE_FLAG[command.program]
    script = next((i for i, arg in enumerate(command.args) if not arg.startswith("-")), None)
    own = command.args[:script]
    long_flags = {arg[2:].split("=", 1)[0] for arg in own if arg.startswith("--")}
    return any(command.has_trailing_short_flag(letter) for letter in letters) or bool(
        long_flags & INLINE_CODE_LONG.get(command.program, frozenset())
    )


AWK_RUNS_COMMAND = re.compile(r"system\s*\(|\|\s*\"|\"\s*\|\s*getline|\|&")

SED_E_COMMAND = re.compile(r"(?:^|[;{}\n])\s*(?:\d+|\$|/[^/]*/)?\s*!?\s*e(?:\s|;|}|$)")
SED_S_E_FLAG = re.compile(r"(?:^|[;{}\n\s])s(.)(?:(?!\1).)*\1(?:(?!\1).)*\1[gpIiMm0-9]*e")


def sed_scripts(command: Command) -> list[str]:
    scripts: list[str] = []
    args = command.args
    for index, arg in enumerate(args):
        if arg in {"-e", "--expression"} and index + 1 < len(args):
            scripts.append(args[index + 1])
        elif arg.startswith("--expression="):
            scripts.append(arg.split("=", 1)[1])
    if not scripts:
        positionals = command.positionals()
        scripts = positionals[:1]
    return scripts


def sed_runs_command(command: Command) -> bool:
    return any(
        SED_E_COMMAND.search(script) or SED_S_E_FLAG.search(script)
        for script in sed_scripts(command)
    )

REGISTRY_RUNNER_MESSAGE = (
    "Fetching a package from a registry and running it is blocked by a static "
    "rule in settings.json. Nobody blocked this interactively. Use a binary the "
    "project already depends on, or add the dependency explicitly first so the "
    "version is recorded. The sibling commands that only run what is already "
    "installed are still available: pnpm exec, yarn exec, bundle exec, "
    "composer exec, dotnet tool run."
)


GH_VALUE_FLAGS = frozenset({"-R", "--repo", "--hostname", "-q", "--jq", "-t", "--template"})

GITHUB_HOST = re.compile(r"(?:^|\.)github\.com$", re.IGNORECASE)

URL_ARGUMENT = re.compile(r"^[a-z][a-z0-9+.\-]*://", re.IGNORECASE)


def flag_value(command: Command, flag: str) -> str | None:
    for index, arg in enumerate(command.args):
        if arg == flag and index + 1 < len(command.args):
            return command.args[index + 1]
        if arg.startswith(f"{flag}="):
            return arg.split("=", 1)[1]
    return None


def gh_words(command: Command) -> tuple[str, ...]:
    words: list[str] = []
    skip = False
    for arg in command.args:
        if skip:
            skip = False
        elif arg in GH_VALUE_FLAGS:
            skip = True
        elif not arg.startswith("-"):
            words.append(arg)
    return tuple(words)


def gh_is(command: Command, *paths: tuple[str, ...]) -> bool:
    if "help" in set(command.long_flags()) or "-h" in command.args:
        return False

    words = gh_words(command)
    return any(words[: len(path)] == path for path in paths)


def gh_leaves_github(command: Command) -> bool:
    if not gh_is(command, ("api",)):
        return False

    hosts = []
    hostname = flag_value(command, "--hostname")
    if hostname:
        hosts.append(hostname)
    for arg in command.args:
        if URL_ARGUMENT.match(arg):
            hosts.append(arg.split("://", 1)[1].split("/", 1)[0].split("@")[-1])

    return any(not GITHUB_HOST.search(host.split(":")[0]) for host in hosts)


OP_VALUE_FLAGS = frozenset({"--account", "--config", "--encoding", "--session"})


def op_words(command: Command) -> tuple[str, ...]:
    words: list[str] = []
    skip = False
    for arg in command.args:
        if skip:
            skip = False
        elif arg in OP_VALUE_FLAGS:
            skip = True
        elif not arg.startswith("-"):
            words.append(arg)
    return tuple(words)


SOCKET_TOOLS = frozenset({"nc", "ncat", "netcat", "telnet"})
HTTP_TOOLS = frozenset({"http", "https", "xh", "xhs", "aria2c", "lynx", "w3m", "links", "elinks"})
HTTP_METHODS = frozenset({"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"})
SOCAT_ADDRESS = re.compile(
    r"^(?:TCP|TCP4|TCP6|OPENSSL|SSL|UDP|UDP4|UDP6|SOCKS4A?|PROXY)[^:]*?:([^:,]+)", re.IGNORECASE
)
SOCKET_VALUE_FLAGS = frozenset({"-p", "-s", "-w", "-i", "-q", "-e", "-c", "-x", "-X", "-I", "-O"})


def is_local_host(host: str) -> bool:
    return bool(LOCAL_TARGET.match(host))


def reaches_remote_host(command: Command) -> bool:
    name = command.program
    if name == "openssl":
        target = flag_value(command, "-connect")
        return command.subcommand_is("s_client") and target is not None and not is_local_host(target)
    if name == "socat":
        hosts = [
            match.group(1)
            for arg in command.args
            if (match := SOCAT_ADDRESS.match(arg)) and "LISTEN" not in arg.upper()
        ]
        return any(not is_local_host(host) for host in hosts)
    if name in SOCKET_TOOLS:
        words = positional_words(command, SOCKET_VALUE_FLAGS)
        hosts = [word for word in words if not word.isdigit()]
        return any(not is_local_host(host) for host in hosts)
    targets = [arg for arg in command.positionals() if arg.upper() not in HTTP_METHODS]
    if not targets:
        return False
    target = targets[0]
    return not (target.startswith(":") or is_local_host(target))


STDOUT_PATH = re.compile(r"^(?:-|/dev/(?:stdout|stderr|tty|fd/[0-9]+)|/proc/self/fd/[0-9]+)$")


def op_prints_secret(command: Command) -> bool:
    if command.substituted:
        return False
    if "help" in set(command.long_flags()) or "-h" in command.args:
        return False

    words = op_words(command)
    long_flags = set(command.long_flags())
    out = flag_value(command, "--out-file") or flag_value(command, "-o")
    writes_file = out is not None and not STDOUT_PATH.match(out)

    if words[:2] == ("item", "get") and "share-link" in long_flags:
        return True
    if words[:1] == ("read",):
        return True
    if words[:1] == ("inject",):
        return not writes_file
    if words[:2] == ("document", "get"):
        return not writes_file
    if words[:2] == ("item", "get"):
        return bool(long_flags & {"reveal", "fields", "otp"}) or (
            (flag_value(command, "--format") or "").lower() == "json"
        )
    return False


def shell_reads_script_from_stdin(command: Command) -> bool:
    if nested_command(command) is not None:
        return False
    if "-" in command.args or set(command.args) & {"<<", "<<-", "<<<"}:
        return True
    return command.piped and (command.has_short_letter("s") or not command.positionals())


def runs_from_registry(command: Command) -> bool:
    positionals = command.positionals()

    if command.name == "npm" and command.subcommand_is("init"):
        return len(positionals) > 1

    pairs = RUNNER_SUBCOMMAND_PAIRS.get(command.name, frozenset())
    if tuple(positionals[:2]) in pairs:
        return True

    first = FIRST_WORD_RUNNERS.get(command.program, frozenset())
    if positionals[:1] and positionals[0] in first:
        return True

    if command.program == "go":
        return go_runs_remote(command)
    if command.program == "deno":
        return deno_runs_remote(command)
    if command.program == "uv":
        return uv_run_fetches(command)

    return command.subcommand_is(*RUNNER_SUBCOMMANDS.get(command.name, frozenset()))


FIRST_WORD_RUNNERS: dict[str, frozenset[str]] = {
    "deno": frozenset({"x"}),
    "cs": frozenset({"launch"}),
    "coursier": frozenset({"launch"}),
    "volta": frozenset({"run"}),
}

GO_VALUE_FLAGS = frozenset(
    {"-C", "-exec", "-tags", "-ldflags", "-gcflags", "-asmflags", "-mod", "-modfile",
     "-overlay", "-pgo", "-p", "-toolexec", "-installsuffix", "-buildmode", "-compiler",
     "-gccgoflags", "-pkgdir", "-coverpkg", "-covermode", "-o"}
)


def go_runs_remote(command: Command) -> bool:
    words = positional_words(command, GO_VALUE_FLAGS)
    return (
        len(words) >= 2
        and words[0] == "run"
        and "@" in words[1]
        and not words[1].startswith((".", "/"))
    )


REMOTE_SPECIFIER = re.compile(r"^(?:npm:|jsr:|https?://)", re.IGNORECASE)
DENO_VALUE_FLAGS = frozenset(
    {"-c", "--config", "--import-map", "--location", "--seed", "--cert", "--lock"}
)


def deno_runs_remote(command: Command) -> bool:
    words = positional_words(command, DENO_VALUE_FLAGS)
    if words[:1] == ("run",):
        words = words[1:]
    return bool(words) and bool(REMOTE_SPECIFIER.match(words[0]))


UV_VALUE_FLAGS = frozenset(
    {"--with", "--with-editable", "--with-requirements", "-p", "--python", "--directory",
     "--project", "--package", "--extra", "--group", "--only-group", "--no-group",
     "--index", "--default-index", "--index-url", "--extra-index-url", "-f",
     "--find-links", "--env-file", "--config-file", "--cache-dir", "-m"}
)


def uv_run_fetches(command: Command) -> bool:
    args = command.args
    index = past_options(args, UV_VALUE_FLAGS)
    if index is None or args[index] != "run":
        return False
    rest = args[index + 1 :]
    target = past_options(rest, UV_VALUE_FLAGS)
    own = rest[:target] if target is not None else rest
    if any(arg == "--with" or arg.startswith("--with=") for arg in own):
        return True
    return target is not None and bool(URL_ARGUMENT.match(rest[target]))


MISE_VALUE_FLAGS = frozenset(
    {"-C", "--cd", "-E", "--env", "-P", "--profile", "-j", "--jobs", "-c", "--command"}
)
MISE_NAMES = frozenset({"mise", "rtx"})


def mise_subcommand(command: Command) -> str | None:
    index = past_options(command.args, MISE_VALUE_FLAGS)
    return command.args[index] if index is not None else None


def mise_exec_fetches(command: Command) -> bool:
    args = command.args
    index = past_options(args, MISE_VALUE_FLAGS)
    if index is None or args[index] != "exec":
        return False
    rest = args[index + 1 :]
    head = rest[: rest.index("--")] if "--" in rest else rest
    skip = False
    for arg in head:
        if skip:
            skip = False
        elif arg in MISE_VALUE_FLAGS:
            skip = True
        elif not arg.startswith("-"):
            return True
    return False


NIX_FETCH_SUBCOMMANDS = frozenset({"run", "shell", "develop"})
NIX_VALUE_FLAGS = frozenset(
    {"--extra-experimental-features", "--experimental-features", "--option", "--arg",
     "--argstr", "-I", "--include", "--override-input", "--inputs-from", "--profile",
     "-f", "--file"}
)
LOCAL_INSTALLABLE = re.compile(r"^(?:\.|/|~|path:|git\+file:)")


def nix_fetches(args: Sequence[str]) -> bool:
    end = next(
        (i for i, arg in enumerate(args) if arg in {"--command", "-c", "--"}), len(args)
    )
    head = args[:end]
    words: list[str] = []
    skip = False
    for arg in head:
        if skip:
            skip = False
        elif arg in NIX_VALUE_FLAGS:
            skip = True
        elif not arg.startswith("-"):
            words.append(arg)
    sub = next((i for i, word in enumerate(words[:2]) if word in NIX_FETCH_SUBCOMMANDS), None)
    if sub is None:
        return False
    if "--expr" in head:
        return True
    file = next(
        (head[i + 1] for i, arg in enumerate(head[:-1]) if arg in {"-f", "--file"}), None
    )
    if file is not None:
        return not LOCAL_INSTALLABLE.match(file)
    installables = words[sub + 1 :]
    if words[sub] == "run":
        installables = installables[:1]
    return any(not LOCAL_INSTALLABLE.match(item) for item in installables)


NIX_SHELL_VALUE_FLAGS = frozenset(
    {"--run", "--command", "-I", "-A", "--attr", "--arg", "--argstr", "--option"}
)


def nix_shell_fetches(command: Command) -> bool:
    if set(command.args) & {"-p", "--packages", "-E", "--expr"}:
        return True
    return any(
        URL_ARGUMENT.match(word) for word in positional_words(command, NIX_SHELL_VALUE_FLAGS)
    )


GIT_VALUE_FLAGS = frozenset(
    {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"}
)


def git_subcommand(command: Command) -> str | None:
    skip = False
    for arg in command.args:
        if skip:
            skip = False
        elif arg in GIT_VALUE_FLAGS:
            skip = True
        elif not arg.startswith("-"):
            return arg
    return None


CHECKOUT_BRANCH_FLAGS = frozenset(
    {
        "-b",
        "--orphan",
        "-q",
        "--quiet",
        "-t",
        "--track",
        "--no-track",
        "--no-guess",
        "--progress",
        "--no-progress",
    }
)

REF_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/@^~+-]*$")


def creates_branch_only(command: Command) -> bool:
    if not command.args or command.args[0] != "checkout":
        return False

    rest = command.args[1:]
    if not {"-b", "--orphan"} & set(rest):
        return False

    flags = [arg for arg in rest if arg.startswith("-")]
    if any(flag not in CHECKOUT_BRANCH_FLAGS for flag in flags):
        return False

    names = [arg for arg in rest if not arg.startswith("-")]
    return 1 <= len(names) <= 2 and all(REF_NAME.match(name) for name in names)


TMUX_DETACHED: dict[str, str] = {
    "new-session": "d",
    "new": "d",
    "new-window": "d",
    "neww": "d",
    "split-window": "d",
    "splitw": "d",
    "run-shell": "b",
    "run": "b",
}
TMUX_VALUE_FLAGS = frozenset({"-L", "-S", "-f", "-c", "-T"})
LAUNCHD_STARTS = frozenset({"submit", "load", "bootstrap", "kickstart", "start"})


def hands_off_to_a_service(command: Command) -> bool:
    name = command.program
    if command.only_prints_info():
        return False
    if name == "coproc":
        return True
    if name in {"at", "batch"}:
        return not command.has_short_letter("lrc")
    if name == "launchctl":
        return command.subcommand_is(*LAUNCHD_STARTS)
    if name == "screen":
        return command.has_short_letter("d") and command.has_short_letter("m")
    words = positional_words(command, TMUX_VALUE_FLAGS)
    flag = TMUX_DETACHED.get(words[0]) if words else None
    return bool(flag) and command.has_short_letter(flag)


def positional_words(command: Command, value_flags: frozenset[str]) -> tuple[str, ...]:
    words: list[str] = []
    skip = False
    for arg in command.args:
        if skip:
            skip = False
        elif arg in value_flags:
            skip = True
        elif not arg.startswith("-"):
            words.append(arg)
    return tuple(words)


DETACH_MESSAGE = (
    "Detaching a command from the Bash tool is blocked by a static rule in "
    "settings.json. Nobody blocked this interactively. The Bash tool starts each "
    "command in its own process group with no controlling terminal and does not "
    "reap it, so a process left behind with `&`, nohup, setsid or disown is "
    "reparented to PID 1, never receives SIGHUP, and outlives the session. Run "
    "the command with `run_in_background: true` instead; if you only need to "
    "wait for something, use the Monitor tool."
)


RULES: Sequence[Rule] = (
    Rule(
        id="background",
        names=frozenset(),
        predicate=lambda c: c.background,
        message=DETACH_MESSAGE,
    ),
    Rule(
        id="detach",
        names=frozenset({"nohup", "setsid", "disown"}),
        predicate=lambda c: c.name == "disown" or not c.only_prints_info(),
        message=DETACH_MESSAGE,
    ),
    Rule(
        id="detach-service",
        names=frozenset({"tmux", "screen", "coproc", "at", "batch", "launchctl"}),
        predicate=lambda c: hands_off_to_a_service(c),
        message=DETACH_MESSAGE,
    ),
    Rule(
        id="rm-forced",
        names=frozenset({"rm"}),
        predicate=lambda c: c.has_short_letter("f") or "force" in set(c.long_flags()),
        message=(
            "Forced rm is blocked by a static rule in settings.json. Nobody "
            "blocked this interactively. -f suppresses the prompts and errors "
            "that would otherwise stop a wrong path from being deleted. Drop the "
            "-f and keep -r if you need a directory, or delete the paths one at "
            "a time."
        ),
    ),
    Rule(
        id="network-fetch",
        names=frozenset({"curl", "wget"}),
        predicate=lambda c: not c.targets_only_localhost()
        and not c.only_prints_info(FETCH_INFO_FLAGS),
        message=(
            "Fetching a remote URL with curl/wget is blocked by a static rule in "
            "settings.json. Nobody blocked this interactively. localhost is "
            "allowed, so checking a server you started yourself still works. For "
            "anything remote, use the WebFetch tool, or the gh CLI for GitHub. "
            "If the page is a SPA that WebFetch cannot render, drive headless "
            "Chrome instead: `timeout 20 <chrome> --headless --disable-gpu "
            "--user-data-dir=$(mktemp -d) --dump-dom <url>`. The timeout is "
            "required, because Chrome does not exit on its own after dumping."
        ),
    ),
    Rule(
        id="network-tool",
        names=SOCKET_TOOLS | HTTP_TOOLS | {"socat", "openssl"},
        predicate=lambda c: reaches_remote_host(c),
        message=(
            "Reaching a remote host with a socket or HTTP tool is blocked by a "
            "static rule in settings.json. Nobody blocked this interactively. "
            "This is the curl rule reached by another route. localhost is "
            "allowed. For a remote page, use the WebFetch tool, or the gh CLI "
            "for GitHub; for anything else, tell the user what you need."
        ),
    ),
    Rule(
        id="git-force-push",
        names=frozenset({"git"}),
        predicate=lambda c: c.subcommand_is("push")
        and (
            c.has_short_letter("f")
            or any(flag.startswith("force") or flag == "mirror" for flag in c.long_flags())
            or any(arg.startswith("+") and len(arg) > 1 for arg in c.positionals())
        ),
        message=(
            "Force-pushing is blocked by a static rule in settings.json. Nobody "
            "blocked this interactively. There is no safe alternative: tell the "
            "user what you want to force-push and why, and let them run it."
        ),
    ),
    Rule(
        id="git-reset",
        names=frozenset({"git"}),
        predicate=lambda c: c.subcommand_is("reset") and "--hard" in c.args,
        message=(
            "git reset --hard is blocked by a static rule in settings.json. "
            "Nobody blocked this interactively. It throws away uncommitted work "
            "with no way back. Use git restore to discard specific files, git "
            "revert to undo a commit, or git reset --soft to move HEAD while "
            "keeping the working tree."
        ),
    ),
    Rule(
        id="chmod-world-writable",
        names=frozenset({"chmod"}),
        predicate=lambda c: any(world_writable(arg) for arg in c.args),
        message=(
            "Making a file writable by everyone, as chmod 777 or o+w does, is "
            "blocked by a static rule in settings.json. Nobody blocked this "
            "interactively. Grant the narrowest mode that works, such as 644 "
            "for files or 755 for executables."
        ),
    ),
    Rule(
        id="keychain-secret-read",
        names=frozenset({"security"}),
        predicate=lambda c: c.subcommand_is(
            "dump-keychain", "find-generic-password", "find-internet-password", "export"
        ),
        message=(
            "Reading secrets out of the macOS keychain is blocked by a static "
            "rule in settings.json. Nobody blocked this interactively. The "
            "secret would be printed straight into the transcript. Ask the "
            "user for it instead. Every other security subcommand still works."
        ),
    ),
    Rule(
        id="op-secret-print",
        names=frozenset({"op"}),
        predicate=op_prints_secret,
        message=(
            "Printing a 1Password secret is blocked by a static rule in "
            "settings.json. Nobody blocked this interactively. The value would "
            "land in the transcript. Hand it straight to the command that needs "
            "it instead: `op run -- <cmd>` with op:// references in the "
            "environment, or `$(op read op://...)` as an argument or assignment "
            "that is never printed. op item list, op vault list, op whoami and "
            "op item get without --reveal, --fields, --otp or --format json "
            "still work."
        ),
    ),
    Rule(
        id="registry-runner",
        names=RUNNER_COMMANDS,
        predicate=lambda c: not c.only_prints_info(),
        message=REGISTRY_RUNNER_MESSAGE,
    ),
    Rule(
        id="registry-runner-subcommand",
        names=frozenset(RUNNER_SUBCOMMANDS)
        | frozenset(RUNNER_SUBCOMMAND_PAIRS)
        | frozenset(FIRST_WORD_RUNNERS)
        | {"go", "deno"},
        predicate=lambda c: runs_from_registry(c),
        message=REGISTRY_RUNNER_MESSAGE,
    ),
    Rule(
        id="mise-x",
        names=MISE_NAMES,
        predicate=lambda c: mise_subcommand(c) == "x",
        message=(
            "mise x is blocked by a static rule in settings.json. Nobody blocked "
            "this interactively. It fetches any tool from any backend and runs "
            "it, the same as npx. Run the tool directly if mise.toml already "
            "pins it, or `mise exec -- <cmd>` with no tool named. If a tool is "
            "missing, tell the user which one, so the version gets recorded."
        ),
    ),
    Rule(
        id="mise-exec-tool",
        names=MISE_NAMES,
        predicate=mise_exec_fetches,
        message=(
            "mise exec with a tool named is blocked by a static rule in "
            "settings.json. Nobody blocked this interactively. Naming a tool "
            "makes mise fetch and install it on the spot, the same as npx. "
            "`mise exec -- <cmd>` with no tool named still runs with the tools "
            "mise.toml pins. If a tool is missing, tell the user which one, so "
            "the version gets recorded."
        ),
    ),
    Rule(
        id="nix-remote-run",
        names=frozenset({"nix", "nix-shell"}),
        predicate=lambda c: nix_shell_fetches(c) if c.name == "nix-shell" else nix_fetches(c.args),
        message=(
            "Running a remote nix installable is blocked by a static rule in "
            "settings.json. Nobody blocked this interactively. nix run, nix "
            "shell and nix develop on nixpkgs#..., github:... or an --expr, and "
            "nix-shell -p, fetch a package and run it, the same as npx. The "
            "project's own flake still works: `nix develop`, `nix run .#app`, "
            "`nix shell .#pkg --command <cmd>`. If a tool is missing, tell the "
            "user which one."
        ),
    ),
    Rule(
        id="sed-in-place",
        names=frozenset({"sed", "gsed"}),
        predicate=lambda c: c.edits_in_place(),
        message=(
            "In-place sed is blocked by a static rule in settings.json. Nobody "
            "blocked this interactively. Use the Edit tool, which shows the diff "
            "and cannot silently rewrite a whole file."
        ),
    ),
    Rule(
        id="interpreter-in-place",
        names=frozenset({"perl", "ruby"}),
        predicate=lambda c: c.edits_in_place(),
        message=(
            "In-place perl/ruby editing is blocked by a static rule in "
            "settings.json. Nobody blocked this interactively. Use the Edit tool "
            "instead."
        ),
    ),
    Rule(
        id="awk-in-place",
        names=frozenset({"awk", "gawk", "mawk", "nawk", "busybox"}),
        predicate=lambda c: "inplace" in c.args
        or any("inplace" in arg for arg in c.args if arg.startswith("-")),
        message=(
            "gawk's inplace extension is blocked by a static rule in "
            "settings.json. Nobody blocked this interactively. It rewrites the "
            "file in place just as sed -i does. Use the Edit tool, or write the "
            "output to a new file with a redirect."
        ),
    ),
    Rule(
        id="text-tool-runs-command",
        names=frozenset({"awk", "gawk", "mawk", "nawk", "sed", "gsed"}),
        predicate=lambda c: sed_runs_command(c)
        if c.program in {"sed", "gsed"}
        else any(AWK_RUNS_COMMAND.search(arg) for arg in c.args),
        message=(
            "Running a shell command from inside an awk or sed program is "
            "blocked by a static rule in settings.json. Nobody blocked this "
            "interactively. system(), a pipe to a quoted command, getline from "
            "one, and sed's e command all hand a string to the shell, out of "
            "the guard's sight. Run that command directly instead."
        ),
    ),
    Rule(
        id="interpreter-inline-code",
        names=INTERPRETERS | {"deno"},
        predicate=runs_inline_code,
        message=(
            "Running a one-liner through an interpreter is blocked by a static "
            "rule in settings.json. Nobody blocked this interactively. Use the "
            "Edit tool to change files: a script that rewrites source tends to "
            "mangle it. If you genuinely need to run code, write it to a file in "
            "the scratchpad directory and run that file, so it stays reviewable."
        ),
    ),
    Rule(
        id="shell-stdin-script",
        names=SHELLS,
        predicate=lambda c: shell_reads_script_from_stdin(c),
        message=(
            "Feeding a script to a shell over a pipe, a heredoc or a here-string "
            "is blocked by a static rule in settings.json. Nobody blocked this "
            "interactively. The guard cannot see what such a script runs. Run "
            "the commands directly, or write the script to the scratchpad "
            "directory and run that file, so it stays reviewable."
        ),
    ),
    Rule(
        id="interpreter-stdin-script",
        names=INTERPRETERS,
        predicate=lambda c: c.reads_stdin_script(),
        message=(
            "Piping a script into an interpreter over stdin is blocked by a "
            "static rule in settings.json. Nobody blocked this interactively. "
            "Write the script to the scratchpad directory and run that file, so "
            "the code stays reviewable."
        ),
    ),
    Rule(
        id="gh-auth",
        names=frozenset({"gh"}),
        predicate=lambda c: gh_is(
            c,
            ("auth", "token"),
            ("auth", "login"),
            ("auth", "logout"),
            ("auth", "refresh"),
            ("auth", "switch"),
            ("auth", "setup-git"),
            ("ssh-key", "add"),
            ("gpg-key", "add"),
            ("repo", "deploy-key", "add"),
        )
        or (
            gh_is(c, ("auth", "status"))
            and ("show-token" in set(c.long_flags()) or c.has_short_letter("t"))
        ),
        message=(
            "Handing out GitHub credentials is blocked by a static rule in "
            "settings.json. Nobody blocked this interactively. Printing a token "
            "puts it in the transcript, and adding a key or refreshing a scope "
            "widens what this session can reach from here on. There is no safe "
            "alternative: tell the user which access you need and let them "
            "grant it. gh auth status still reports the account and its scopes."
        ),
    ),
    Rule(
        id="gh-config-persist",
        names=frozenset({"gh"}),
        predicate=lambda c: gh_is(
            c,
            ("alias", "set"),
            ("alias", "import"),
            ("config", "set"),
            ("extension", "install"),
            ("extension", "upgrade"),
            ("skill", "install"),
            ("skill", "update"),
        ),
        message=(
            "Writing gh's persistent configuration is blocked by a static rule "
            "in settings.json. Nobody blocked this interactively. An alias, a "
            "pager, an extension or a skill outlives this session and can carry "
            "any command with it. Whatever the work at hand needs can be passed "
            "as a flag or an environment variable instead; making it permanent "
            "is the user's call."
        ),
    ),
    Rule(
        id="gh-agent-spawn",
        names=frozenset({"gh"}),
        predicate=lambda c: gh_is(c, ("copilot",)),
        message=(
            "Starting the Copilot CLI is blocked by a static rule in "
            "settings.json. Nobody blocked this interactively. It fetches and "
            "runs a second agent that holds its own shell access, outside every "
            "rule here. Do the work with the tools in this session, or tell the "
            "user what you want run."
        ),
    ),
    Rule(
        id="gh-api-remote",
        names=frozenset({"gh"}),
        predicate=gh_leaves_github,
        message=(
            "Fetching a non-GitHub host through gh api is blocked by a static "
            "rule in settings.json. Nobody blocked this interactively. This is "
            "the curl rule reached by another route. Use the WebFetch tool for a "
            "remote page; gh api against github.com is unaffected."
        ),
    ),
    Rule(
        id="gh-irreversible-delete",
        names=frozenset({"gh"}),
        predicate=lambda c: gh_is(
            c,
            ("repo", "delete"),
            ("project", "delete"),
            ("project", "item-delete"),
            ("project", "field-delete"),
        ),
        message=(
            "Deleting a repository or a project through gh is blocked by a "
            "static rule in settings.json. Nobody blocked this interactively. "
            "Neither comes back, and everything filed against them goes too. "
            "There is no safe alternative: tell the user what should be removed "
            "and let them do it."
        ),
    ),
    Rule(
        id="gh-repo-publish",
        names=frozenset({"gh"}),
        predicate=lambda c: gh_is(c, ("repo", "edit"))
        and (flag_value(c, "--visibility") or "").lower() == "public",
        message=(
            "Making a repository public is blocked by a static rule in "
            "settings.json. Nobody blocked this interactively. Disclosure cannot "
            "be taken back: once the code has been fetched, setting it private "
            "again changes nothing. Tell the user what you would publish and let "
            "them decide."
        ),
    ),
    Rule(
        id="gh-ci-config",
        names=frozenset({"gh"}),
        decision="ask",
        predicate=lambda c: gh_is(
            c,
            ("secret", "set"),
            ("secret", "delete"),
            ("variable", "set"),
            ("variable", "delete"),
        ),
        message=(
            "This changes what the repository's workflows run with. A secret "
            "cannot be read back, so overwriting one loses the old value."
        ),
    ),
    Rule(
        id="gh-remote-delete",
        names=frozenset({"gh"}),
        decision="ask",
        predicate=lambda c: gh_is(
            c,
            ("release", "delete"),
            ("release", "delete-asset"),
            ("issue", "delete"),
            ("gist", "delete"),
            ("run", "delete"),
        ),
        message=(
            "This deletes something on GitHub that does not come back. A run "
            "takes its logs with it."
        ),
    ),
    Rule(
        id="gh-remote-run",
        names=frozenset({"gh"}),
        decision="ask",
        predicate=lambda c: gh_is(c, ("workflow", "run"), ("agent-task", "create")),
        message="This starts work on GitHub's machines, and it bills.",
    ),
    Rule(
        id="gh-repo-sync-force",
        names=frozenset({"gh"}),
        decision="ask",
        predicate=lambda c: gh_is(c, ("repo", "sync"))
        and ("force" in set(c.long_flags()) or c.has_short_letter("f")),
        message=(
            "This resets the branch to match the other side, discarding "
            "commits it does not have."
        ),
    ),
    Rule(
        id="git-clean-force",
        names=frozenset({"git"}),
        decision="ask",
        predicate=lambda c: c.subcommand_is("clean")
        and (c.has_short_letter("f") or "force" in set(c.long_flags()))
        and not (c.has_short_letter("n") or "dry-run" in set(c.long_flags())),
        message=(
            "This deletes untracked files outright. Nothing in git can bring "
            "them back."
        ),
    ),
    Rule(
        id="git-history-rewrite",
        names=frozenset({"git"}),
        decision="ask",
        predicate=lambda c: c.subcommand_is("filter-branch", "filter-repo")
        or (c.subcommand_is("reflog") and "expire" in c.positionals())
        or (
            c.subcommand_is("gc")
            and any(arg in {"--prune=now", "--prune=all"} for arg in c.args)
        ),
        message=(
            "This rewrites history and drops the reflog entries that would "
            "otherwise undo it."
        ),
    ),
    Rule(
        id="git-restore-worktree",
        names=frozenset({"git"}),
        decision="ask",
        predicate=lambda c: c.subcommand_is("restore")
        and "." in c.positionals()[1:]
        and not (
            "staged" in set(c.long_flags()) and "worktree" not in set(c.long_flags())
        ),
        message=(
            "This throws away every uncommitted change in the working tree, "
            "the same as git reset --hard would."
        ),
    ),
    Rule(
        id="git-stash-discard",
        names=frozenset({"git"}),
        decision="ask",
        predicate=lambda c: c.subcommand_is("stash")
        and bool({"drop", "clear"} & set(c.positionals()[1:3])),
        message="This throws away stashed work, which nothing else holds.",
    ),
    Rule(
        id="git-push-delete",
        names=frozenset({"git"}),
        decision="ask",
        predicate=lambda c: c.subcommand_is("push")
        and (
            bool({"delete", "prune"} & set(c.long_flags()))
            or c.has_short_letter("d")
            or any(arg.startswith(":") and len(arg) > 1 for arg in c.positionals())
        ),
        message="This removes branches from the remote.",
    ),
    Rule(
        id="variable-command",
        names=frozenset(),
        decision="ask",
        predicate=lambda c: c.name.startswith("$"),
        message=(
            "This runs whatever the variable or substitution holds, which the "
            "guard cannot see."
        ),
    ),
    Rule(
        id="git-checkout-branch",
        names=frozenset({"git"}),
        decision="allow",
        predicate=creates_branch_only,
        message="Creating a branch only moves HEAD; the working tree is untouched.",
    ),
    Rule(
        id="git-rebase-resume",
        names=frozenset({"git"}),
        decision="allow",
        predicate=lambda c: c.args in {("rebase", "--abort"), ("rebase", "--continue")},
        message="Finishing or abandoning a rebase already in progress; no history is rewritten.",
    ),
    Rule(
        id="git-commit",
        names=frozenset({"git"}),
        decision="ask",
        predicate=lambda c: git_subcommand(c) == "commit",
        message="This records a commit on the current branch.",
    ),
    Rule(
        id="git-push",
        names=frozenset({"git"}),
        decision="ask",
        predicate=lambda c: git_subcommand(c) == "push",
        message="This publishes commits to the remote, where others can fetch them.",
    ),
    Rule(
        id="git-rebase",
        names=frozenset({"git"}),
        decision="ask",
        predicate=lambda c: git_subcommand(c) == "rebase",
        message="This rewrites the commits of the current branch.",
    ),
    Rule(
        id="git-checkout",
        names=frozenset({"git"}),
        decision="ask",
        predicate=lambda c: git_subcommand(c) == "checkout",
        message=(
            "This switches branches, or overwrites files in the working tree "
            "with another version of them."
        ),
    ),
)


def shield(char: str) -> str:
    return QUOTED_AMPERSAND if char == "&" else char


HEREDOC_TEXT_SINKS = frozenset({"cat", "tee", "git", "gh"})


def heredoc_consumer(result: list[str]) -> str:
    text = "".join(result)
    start = max(text.rfind(sep) for sep in ";|&(\n") + 1
    for word in text[start:].split():
        if not ASSIGNMENT.match(word):
            return word.rsplit("/", 1)[-1]
    return ""


def skip_heredoc_bodies(
    command_line: str, index: int, pending: list[tuple[str, bool, bool]], result: list[str]
) -> int:
    for delimiter, strip_tabs, inert in pending:
        while index < len(command_line):
            end = command_line.find("\n", index)
            line_end = len(command_line) if end == -1 else end
            line = command_line[index:line_end]
            index = line_end + 1
            if (line.lstrip("\t") if strip_tabs else line) == delimiter:
                break
            if not inert:
                result.append(line + "\n")
    result.append("\n")
    return index


def strip_comments(command_line: str) -> str:
    result: list[str] = []
    quote = ""
    at_word_start = True
    index = 0
    pending: list[tuple[str, bool, bool, int]] = []
    depth = 0
    reopen: list[int] = []
    backtick_reopens = False

    while index < len(command_line):
        char = command_line[index]

        if quote == '"' and command_line.startswith("$(", index):
            result.append('"$(')
            quote = ""
            depth += 1
            reopen.append(depth)
            at_word_start = True
            index += 2
            continue

        if quote == '"' and char == "`":
            result.append('"`')
            quote = ""
            backtick_reopens = True
            at_word_start = True
            index += 1
            continue

        if quote:
            if char == "\\" and quote == '"' and index + 1 < len(command_line):
                result.append(char)
                result.append(shield(command_line[index + 1]))
                index += 2
                continue
            result.append(shield(char) if char != quote else char)
            if char == quote:
                quote = ""
            index += 1
            continue

        if char == "\\" and index + 1 < len(command_line):
            result.append(char)
            result.append(shield(command_line[index + 1]))
            index += 2
            at_word_start = False
            continue

        if char in "'\"":
            quote = char
            result.append(char)
            at_word_start = False
            index += 1
            continue

        if char == "#" and at_word_start:
            while index < len(command_line) and command_line[index] not in "\r\n":
                index += 1
            continue

        heredoc = HEREDOC.match(command_line, index) if char == "<" else None
        if heredoc:
            inert = bool(heredoc.group("quoted")) and heredoc_consumer(result) in HEREDOC_TEXT_SINKS
            result.append(heredoc.group(0))
            pending.append(
                (heredoc.group("word"), bool(heredoc.group("tabs")), inert, heredoc.end())
            )
            at_word_start = False
            index = heredoc.end()
            continue

        if char == "\n" and pending:
            result.append(char)
            bodies = [
                (word, tabs, inert and "|" not in command_line[op_end:index])
                for word, tabs, inert, op_end in pending
            ]
            index = skip_heredoc_bodies(command_line, index + 1, bodies, result)
            pending = []
            at_word_start = True
            continue

        if char == ")" and reopen and reopen[-1] == depth:
            reopen.pop()
            depth -= 1
            result.append(')"')
            quote = '"'
            index += 1
            continue

        if char == "`" and backtick_reopens:
            result.append('`"')
            quote = '"'
            backtick_reopens = False
            index += 1
            continue

        if char == "(":
            depth += 1
        elif char == ")":
            depth = max(depth - 1, 0)

        result.append(char)
        at_word_start = char.isspace() or char in ";|&()"
        index += 1

    return "".join(result)


def tokenize(command_line: str) -> tuple[list[str], bool]:
    without_comments = strip_comments(command_line)
    prepared = (
        without_comments.replace("\n", " ; ").replace("\r", " ; ").replace("`", " ; ")
    )

    lexer = shlex.shlex(prepared, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    malformed = False
    try:
        tokens = list(lexer)
    except ValueError:
        malformed = True
        rough = re.sub(r"(\|\||&&|;|\||(?<![<>])&(?!>)|\(|\)|\{|\})", " \\1 ", prepared)
        tokens = [token.strip("\"'") for token in rough.split() if token.strip("\"'")]

    result: list[str] = []
    for token in tokens:
        result.extend(split_operators(token))
    return result, malformed


def split_operators(token: str) -> list[str]:
    if not token or set(token) - PUNCTUATION:
        return [token]

    parts: list[str] = []
    while token:
        for width in range(min(3, len(token)), 0, -1):
            if token[:width] in OPERATORS:
                parts.append(token[:width])
                token = token[width:]
                break
        else:
            parts.append(token[0])
            token = token[1:]
    return parts


def normalize(
    tokens: list[str], background: bool = False, substituted: bool = False
) -> Command | None:
    tokens = [token.replace(QUOTED_AMPERSAND, "&") for token in tokens]
    original_length = len(tokens)

    changed = True
    while changed and tokens:
        changed = False

        while tokens and (tokens[0] in KEYWORDS or ASSIGNMENT.match(tokens[0])):
            tokens.pop(0)
            changed = True

        marker = next(
            (i for i, token in enumerate(tokens) if token in {"--command", "-c"}), None
        )
        if (
            tokens
            and tokens[0] == "nix"
            and marker is not None
            and not nix_fetches(tokens[1:])
        ):
            del tokens[: marker + 1]
            changed = True

        wrapper = tokens[0].rsplit("/", 1)[-1] if tokens else ""
        if wrapper in WRAPPERS:
            tokens.pop(0)
            value_flags = WRAPPER_VALUE_FLAGS.get(wrapper, frozenset())
            changed = True
            while tokens and (tokens[0].startswith("-") or DURATION.match(tokens[0])):
                flag = tokens.pop(0)
                if flag in value_flags and tokens and not tokens[0].startswith("-"):
                    tokens.pop(0)
            del tokens[: WRAPPER_POSITIONALS.get(wrapper, 0)]

    if not tokens:
        return None

    name = tokens[0]
    if "/" in name:
        name = name.rsplit("/", 1)[1]

    return Command(
        name=name,
        args=tuple(tokens[1:]),
        raw=" ".join(tokens),
        background=background,
        prefixed=len(tokens) != original_length or name != tokens[0],
        substituted=substituted,
    )


def split_commands(command_line: str) -> tuple[list[Command], bool]:
    commands: list[Command] = []
    current: list[str] = []
    substituted = False
    piped = False

    tokens, malformed = tokenize(command_line)
    for token in tokens:
        if token in SEPARATORS:
            command = normalize(current, background=token == "&", substituted=substituted)
            if command:
                commands.append(replace(command, piped=piped))
            substituted = token == "(" and bool(current) and current[-1].endswith("$")
            piped = token in {"|", "|&"}
            current = []
        else:
            current.append(token)

    command = normalize(current, substituted=substituted)
    if command:
        commands.append(replace(command, piped=piped))

    return commands, malformed


SSH_VALUE_FLAGS = frozenset(
    {"-B", "-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L", "-l", "-m",
     "-O", "-o", "-P", "-p", "-Q", "-R", "-S", "-W", "-w"}
)


def remote_command(args: Sequence[str]) -> str | None:
    skip = False
    for index, arg in enumerate(args):
        if skip:
            skip = False
        elif arg in SSH_VALUE_FLAGS:
            skip = True
        elif arg == "--":
            continue
        elif not arg.startswith("-"):
            rest = args[index + 1 :]
            return " ".join(rest) if rest else None
    return None


CONTAINER_VALUE_FLAGS = frozenset(
    {"-e", "--env", "--env-file", "-u", "--user", "-w", "--workdir", "-v", "--volume",
     "-p", "--publish", "--name", "--network", "--net", "--entrypoint", "--platform",
     "-m", "--memory", "--cpus", "--mount", "-l", "--label", "--add-host", "-h",
     "--hostname", "--restart", "--pull", "--cap-add", "--cap-drop", "--device",
     "--dns", "--ulimit", "--tmpfs", "--gpus", "--detach-keys", "--arch", "--os",
     "-c", "--cpu-shares"}
)
CONTAINER_TOOLS = frozenset({"docker", "podman", "nerdctl", "container"})
FIND_EXEC_FLAGS = frozenset({"-exec", "-execdir", "-ok", "-okdir"})


def past_options(args: Sequence[str], value_flags: frozenset[str]) -> int | None:
    skip = False
    for index, arg in enumerate(args):
        if skip:
            skip = False
        elif arg in value_flags:
            skip = True
        elif arg != "--" and not arg.startswith("-"):
            return index
    return None


def after_target(args: Sequence[str], value_flags: frozenset[str]) -> str | None:
    index = past_options(args, value_flags)
    rest = args[index + 1 :] if index is not None else ()
    return shlex.join(rest) if rest else None


def after_double_dash(args: Sequence[str]) -> str | None:
    if "--" not in args:
        return None
    rest = args[args.index("--") + 1 :]
    return shlex.join(rest) if rest else None


def relayed_command(command: Command) -> str | None:
    name = command.program.lower()
    args = command.args

    if name == "eval":
        return " ".join(args) or None
    if name == "watch":
        index = past_options(args, frozenset({"-n", "--interval"}))
        return " ".join(args[index:]) if index is not None else None
    if name == "find":
        start = next((i for i, arg in enumerate(args) if arg in FIND_EXEC_FLAGS), None)
        if start is None:
            return None
        rest = [arg for arg in args[start + 1 :] if arg != "+"]
        return shlex.join(rest) if rest else None
    if name in CONTAINER_TOOLS:
        if args[:2] in {("compose", "exec"), ("compose", "run")}:
            args = args[1:]
        if args[:1] in {("exec",), ("run",)}:
            return after_target(args[1:], CONTAINER_VALUE_FLAGS)
        return None
    if name == "limactl" and args[:1] == ("shell",):
        return after_target(args[1:], frozenset({"--workdir", "--shell"}))
    if name == "nix-shell":
        return flag_value(command, "--run") or flag_value(command, "--command")
    if name == "ssh":
        return remote_command(args)
    if name == "tailscale" and args[:1] == ("ssh",):
        return remote_command(args[1:])
    if name == "k3s" and args[:1] == ("kubectl",):
        args = args[1:]
        name = "kubectl"
    head = args[: args.index("--")] if "--" in args else args
    if name in {"kubectl", "oc"} and "exec" in head:
        return after_double_dash(args)
    if name in MISE_NAMES and mise_subcommand(command) in {"exec", "x"}:
        inline = flag_value(command, "--command") or flag_value(command, "-c")
        return inline or after_double_dash(args)
    return None


def nested_command(command: Command) -> str | None:
    if command.name not in SHELLS:
        return None

    for index, arg in enumerate(command.args):
        if not arg.startswith("-") or arg.startswith("--"):
            continue
        if "c" in arg[1:]:
            for candidate in command.args[index + 1 :]:
                if candidate != "--":
                    return candidate
            return None

    return None


def match_all(
    command_line: str, depth: int = 0
) -> tuple[list[tuple[Rule | None, Command]], bool]:
    matches: list[tuple[Rule | None, Command]] = []
    commands, malformed = split_commands(command_line)
    for command in commands:
        matches.append((next((r for r in RULES if r.matches(command)), None), command))

        if depth == 0:
            payload = nested_command(command) or relayed_command(command)
            if payload:
                inner, inner_malformed = match_all(payload, depth + 1)
                matches.extend(inner)
                malformed = malformed or inner_malformed

    return matches, malformed


def decide(command_line: str) -> tuple[Rule, Command] | None:
    matches, malformed = match_all(command_line)
    for decision in ("deny", "ask"):
        for rule, command in matches:
            if rule and rule.decision == decision:
                return rule, command

    if malformed:
        return fallback_ask(matches)

    if matches and all(
        rule and rule.decision == "allow" and not command.prefixed
        for rule, command in matches
    ):
        return matches[0][0], matches[0][1]

    return fallback_ask(matches)


def fallback_ask(matches: list[tuple[Rule | None, Command]]) -> tuple[Rule, Command] | None:
    for rule, command in matches:
        if rule and rule.decision == "allow":
            ask = next((r for r in RULES if r.decision == "ask" and r.matches(command)), None)
            if ask:
                return ask, command

    return None


def abbreviate(text: str, limit: int = ECHO_LIMIT) -> str:
    if len(text) <= limit:
        return text

    marker_budget = len(f" ... (+{len(text)} chars)")
    head = text[: limit - marker_budget]
    return f"{head} ... (+{len(text) - len(head)} chars)"


NO_WORKAROUND = (
    "Do not run the same thing written another way to get past this rule. "
    "Take the alternative named above; if the user asked for exactly this "
    "action, ask them for approval with the AskUserQuestion tool instead."
)


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError, ValueError):
        return 0

    if not isinstance(payload, dict) or payload.get("tool_name") != "Bash":
        return 0

    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return 0

    command_line = tool_input.get("command")
    if not isinstance(command_line, str) or not command_line.strip():
        return 0

    verdict = decide(command_line)
    if verdict is None:
        return 0

    rule, command = verdict

    if rule.decision in {"ask", "allow"}:
        json.dump(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": rule.decision,
                    "permissionDecisionReason": rule.message,
                }
            },
            sys.stdout,
        )
        return 0

    print(
        f"{rule.message}\n\n{NO_WORKAROUND}\n\nBlocked sub-command: {abbreviate(command.raw)}",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
