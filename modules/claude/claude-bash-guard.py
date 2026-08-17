#!@python3@
"""PreToolUse guard for the Bash tool.

Replaces the Bash entries of permissions.deny. A deny rule can only say "no",
and the model reads that bare refusal as the user having blocked it, so it
stops. Exiting 2 here sends stderr back to the model as the reason, which lets
each rule name its own alternative and keeps the turn going.

Fails open: a malformed payload lets the call through to the normal permission
flow. Real containment belongs to the sandbox settings.
"""

from __future__ import annotations

import json
import re
import shlex
import sys
from dataclasses import dataclass, field
from typing import Callable, Iterator, Sequence

# Tokens that end one command and open the next. Splitting on them stops a rule
# from being evaded by hiding the call behind && or inside a substitution.
SEPARATORS = frozenset({"&&", "||", ";", ";;", "|", "|&", "&", "(", ")", "{", "}"})

# Keywords that open a command position, so `then git reset --hard` still gets
# checked as a `git reset`.
KEYWORDS = frozenset({"then", "else", "elif", "do", "done", "fi", "esac", "!"})

# Commands that only prefix another command. Stripping them stops a rule from
# being sidestepped by `env sed -i ...` or `xargs rm -rf`.
WRAPPERS = frozenset(
    {
        "builtin",
        "command",
        "doas",
        "env",
        "exec",
        "nice",
        "nohup",
        "setsid",
        "stdbuf",
        "sudo",
        "time",
        "timeout",
        "xargs",
    }
)

# Redirections that feed a script in over stdin.
STDIN_REDIRECTS = frozenset({"<", "<<", "<<<", "<<-"})

ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
DURATION = re.compile(r"^[0-9]+[smhd]?$")
OCTAL_MODE = re.compile(r"^[0-7]{3,4}$")

# A fetch target that stays on this machine. Anything that is not clearly local
# is treated as remote, so an unrecognized form fails toward blocking.
LOCAL_TARGET = re.compile(
    r"^(?:[a-z][a-z0-9+.\-]*://)?"
    r"(?:\[::1\]|::1|localhost|127(?:\.[0-9]{1,3}){3}|0\.0\.0\.0)"
    r"(?::[0-9]+)?(?:[/?#]|$)",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Command:
    """One normalized sub-command: the program plus its arguments."""

    name: str
    args: tuple[str, ...]
    raw: str

    def short_flag_clusters(self) -> Iterator[str]:
        """Letter runs of each short flag: -pi.bak yields 'pi', -rf yields 'rf'."""
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
        """True when a short flag ends in `letter`, as -pi or -pe do.

        A flag that takes a value has to sit last in its cluster, so anchoring
        at the end is what separates `perl -pe` from `ruby -rerb` and
        `perl -Mstrict`, where the letter merely appears inside a module name.
        """
        return any(cluster.endswith(letter) for cluster in self.short_flag_clusters())

    def edits_in_place(self) -> bool:
        return self.has_trailing_short_flag("i") or "in-place" in set(self.long_flags())

    def positionals(self) -> list[str]:
        return [arg for arg in self.args if not arg.startswith("-")]

    def subcommand_is(self, *names: str) -> bool:
        """True when a subcommand appears where one can legally sit.

        Only args[0] is not enough: global flags come first, so `pnpm --silent
        dlx foo` would slip past. Looking at the first two positionals covers a
        flag that eats a value, as in `yarn --cwd . dlx foo`, without matching a
        package name further along.
        """
        return bool(set(self.positionals()[:2]) & set(names))

    def reads_stdin_script(self) -> bool:
        return "-" in self.args or bool(set(self.args) & STDIN_REDIRECTS)

    def fetch_targets(self) -> list[str]:
        """Arguments that name something to fetch, local or not."""
        return [
            arg
            for arg in self.args
            if not arg.startswith("-") and ("://" in arg or LOCAL_TARGET.match(arg))
        ]

    def targets_only_localhost(self) -> bool:
        targets = self.fetch_targets()
        return bool(targets) and all(LOCAL_TARGET.match(target) for target in targets)


@dataclass(frozen=True)
class Rule:
    """A block rule.

    `names` selects the programs it applies to; `predicate` narrows further.
    The message states that the block is a static setting rather than a live
    refusal, and names what to do instead.
    """

    id: str
    names: frozenset[str]
    message: str
    predicate: Callable[[Command], bool] = field(default=lambda _: True)

    def matches(self, command: Command) -> bool:
        return command.name in self.names and self.predicate(command)


# Commands whose whole purpose is to fetch a package and run it. The name alone
# decides, so no argument inspection is needed.
RUNNER_COMMANDS = frozenset({"npx", "pnpx", "pnx", "bunx", "uvx", "dnx", "jbang"})

# Package managers that fetch and run only under a particular subcommand. The
# sibling subcommands that run something already installed stay available:
# pnpm exec, yarn exec, bundle exec, composer exec, dotnet tool run.
RUNNER_SUBCOMMANDS: dict[str, frozenset[str]] = {
    "npm": frozenset({"exec", "x", "create"}),
    "pnpm": frozenset({"dlx", "create"}),
    "yarn": frozenset({"dlx", "create"}),
    "bun": frozenset({"x", "create"}),
    "pipx": frozenset({"run", "install"}),
    "gem": frozenset({"exec"}),
    "dotnet": frozenset({"dnx"}),
    # Corepack downloads the package manager itself, then hands off to it, so
    # every shim it exposes is a way around the rules above.
    "corepack": frozenset(
        {"npm", "npx", "pnpm", "pnpx", "yarn", "yarnpkg", "install", "use", "up"}
    ),
}

# The same thing, for tools that spell it with two words.
RUNNER_SUBCOMMAND_PAIRS: dict[str, frozenset[tuple[str, str]]] = {
    "uv": frozenset({("tool", "run"), ("tool", "install")}),
    "dotnet": frozenset({("tool", "exec")}),
}

REGISTRY_RUNNER_MESSAGE = (
    "Fetching a package from a registry and running it is blocked by a static "
    "rule in settings.json. Nobody blocked this interactively. Use a binary the "
    "project already depends on, or add the dependency explicitly first so the "
    "version is recorded. The sibling commands that only run what is already "
    "installed are still available: pnpm exec, yarn exec, bundle exec, "
    "composer exec, dotnet tool run."
)


def runs_from_registry(command: Command) -> bool:
    """True when a package manager was asked to fetch and run something."""
    positionals = command.positionals()

    # `npm init <initializer>` becomes `npm exec create-<initializer>`, but a
    # bare `npm init` only writes a package.json.
    if command.name == "npm" and command.subcommand_is("init"):
        return len(positionals) > 1

    pairs = RUNNER_SUBCOMMAND_PAIRS.get(command.name, frozenset())
    if tuple(positionals[:2]) in pairs:
        return True

    return command.subcommand_is(*RUNNER_SUBCOMMANDS.get(command.name, frozenset()))


RULES: Sequence[Rule] = (
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
        predicate=lambda c: not c.targets_only_localhost(),
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
        id="git-force-push",
        names=frozenset({"git"}),
        predicate=lambda c: c.subcommand_is("push")
        and (
            c.has_short_letter("f")
            or any(flag.startswith("force") for flag in c.long_flags())
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
        predicate=lambda c: any(
            (OCTAL_MODE.match(arg) and arg.endswith("777")) or arg in {"a+rwx", "ugo+rwx"}
            for arg in c.args
        ),
        message=(
            "chmod 777 is blocked by a static rule in settings.json. Nobody "
            "blocked this interactively. Grant the narrowest mode that works, "
            "such as 644 for files or 755 for executables."
        ),
    ),
    Rule(
        id="registry-runner",
        names=RUNNER_COMMANDS,
        message=REGISTRY_RUNNER_MESSAGE,
    ),
    Rule(
        id="registry-runner-subcommand",
        names=frozenset(RUNNER_SUBCOMMANDS) | frozenset(RUNNER_SUBCOMMAND_PAIRS),
        predicate=lambda c: runs_from_registry(c),
        message=REGISTRY_RUNNER_MESSAGE,
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
        id="interpreter-inline-code",
        names=frozenset({"python", "python3", "node", "ruby", "perl"}),
        predicate=lambda c: c.has_trailing_short_flag(
            "c" if c.name.startswith("python") else "e"
        ),
        message=(
            "Running a one-liner through an interpreter is blocked by a static "
            "rule in settings.json. Nobody blocked this interactively. Use the "
            "Edit tool to change files: a script that rewrites source tends to "
            "mangle it. If you genuinely need to run code, write it to a file in "
            "the scratchpad directory and run that file, so it stays reviewable."
        ),
    ),
    Rule(
        id="interpreter-stdin-script",
        names=frozenset({"python", "python3", "node", "ruby", "perl"}),
        predicate=lambda c: c.reads_stdin_script(),
        message=(
            "Piping a script into an interpreter over stdin is blocked by a "
            "static rule in settings.json. Nobody blocked this interactively. "
            "Write the script to the scratchpad directory and run that file, so "
            "the code stays reviewable."
        ),
    ),
)


def tokenize(command_line: str) -> list[str]:
    """Split a command line into shell tokens, keeping operators separate.

    Newlines and backticks become explicit separators first: shlex treats a
    newline as plain whitespace, which would splice two commands into one, and
    it has no notion of a backtick substitution at all.
    """
    prepared = command_line.replace("\n", " ; ").replace("\r", " ; ").replace("`", " ; ")

    lexer = shlex.shlex(prepared, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    try:
        return list(lexer)
    except ValueError:
        # Unbalanced quotes. Fall back to a crude split rather than skipping the
        # check, so a malformed command cannot be used to slip a rule.
        rough = re.sub(r"(\|\||&&|;|\||&|\(|\)|\{|\})", " \\1 ", prepared)
        return [token.strip("\"'") for token in rough.split() if token.strip("\"'")]


def normalize(tokens: list[str]) -> Command | None:
    """Strip everything that only prefixes the real command."""
    tokens = list(tokens)

    changed = True
    while changed and tokens:
        changed = False

        while tokens and (tokens[0] in KEYWORDS or ASSIGNMENT.match(tokens[0])):
            tokens.pop(0)
            changed = True

        if tokens and tokens[0] in WRAPPERS:
            tokens.pop(0)
            changed = True
            # Wrappers carry flags, and some carry a value of their own such as
            # `timeout 30` or `nice -n 10`.
            while tokens and (tokens[0].startswith("-") or DURATION.match(tokens[0])):
                tokens.pop(0)

    if not tokens:
        return None

    name = tokens[0]
    if "/" in name:
        name = name.rsplit("/", 1)[1]

    return Command(name=name, args=tuple(tokens[1:]), raw=" ".join(tokens))


def split_commands(command_line: str) -> list[Command]:
    commands: list[Command] = []
    current: list[str] = []

    for token in tokenize(command_line):
        if token in SEPARATORS:
            command = normalize(current)
            if command:
                commands.append(command)
            current = []
        else:
            current.append(token)

    command = normalize(current)
    if command:
        commands.append(command)

    return commands


def find_violation(command_line: str) -> tuple[Rule, Command] | None:
    for command in split_commands(command_line):
        for rule in RULES:
            if rule.matches(command):
                return rule, command
    return None


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

    violation = find_violation(command_line)
    if violation is None:
        return 0

    rule, command = violation
    print(f"{rule.message}\n\nBlocked sub-command: {command.raw}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
