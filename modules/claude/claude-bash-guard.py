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

# Tokens that only redirect. A run of punctuation that is none of these and
# none of SEPARATORS, such as the `&)` that closes `(cmd &)`, is a splice of
# several and gets split back apart.
REDIRECTS = frozenset({"<", "<<", "<<<", "<<-", "<&", "<>", ">", ">>", ">&", ">|", "&>", "&>>"})
OPERATORS = SEPARATORS | REDIRECTS
PUNCTUATION = frozenset("();<>|&")

# Stands in for an `&` that sits inside quotes or behind a backslash while the
# line is tokenized, since shlex hands both back as a bare `&`, which would
# read as a background operator. Restored once the tokens are apart.
QUOTED_AMPERSAND = "\x00amp\x00"

# Commands that only prefix another command. Stripping them stops a rule from
# being sidestepped by `env sed -i ...` or `xargs rm -rf`. nohup and setsid are
# not here: they detach the command, which is a rule of its own.
WRAPPERS = frozenset(
    {
        "builtin",
        "command",
        "doas",
        "env",
        "exec",
        "nice",
        "stdbuf",
        "sudo",
        "time",
        "timeout",
        "xargs",
    }
)

# Skipping a flag but not its value leaves the value in command position, so
# the real command is never examined. Only flags that always take a separate
# value belong here -- an optional or joined one would eat the command itself,
# which is the same failure. That rules out `sudo -h` and `xargs -i`.
WRAPPER_VALUE_FLAGS: dict[str, frozenset[str]] = {
    "doas": frozenset({"-u", "-C"}),
    "env": frozenset({"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}),
    "nice": frozenset({"-n", "--adjustment"}),
    "stdbuf": frozenset({"-i", "-o", "-e", "--input", "--output", "--error"}),
    "sudo": frozenset({"-u", "-g", "-U", "-C", "-p", "-r", "-t"}),
    "timeout": frozenset({"-s", "--signal", "-k", "--kill-after"}),
    "xargs": frozenset({"-I", "-n", "-P", "-s", "-L", "-E", "-d", "-a"}),
}

STDIN_REDIRECTS = frozenset({"<", "<<", "<<<", "<<-"})

# The tokenizer hands a shell's -c argument over intact, so nothing inside it
# meets a rule unless it is unpacked deliberately.
SHELLS = frozenset({"bash", "sh", "zsh", "dash", "ksh", "fish"})

# Cap on the sub-command echoed back in a block message. Across every
# transcript only the interpreter rules run long enough to matter, and their
# messages already name the fix, so echoing the inlined program adds nothing.
ECHO_LIMIT = 200

ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
VERSION_SUFFIX = re.compile(r"[0-9.]+$")
DURATION = re.compile(r"^[0-9]+[smhd]?$")
OCTAL_MODE = re.compile(r"^[0-7]{3,4}$")

# A fetch target that stays on this machine. Anything that is not clearly local
# is treated as remote, so an unrecognized form fails toward blocking.
LOCAL_TARGET = re.compile(
    r"^(?:[a-z][a-z0-9+.\-]*://)?"
    r"(?:\[::1\]|::1|localhost|127(?:\.[0-9]{1,3}){3}|0\.0\.0\.0)"
    # The port is often a shell variable, so anything up to the path counts --
    # except `@`, which ends the userinfo: past it the match is not the host.
    r"(?::[^/?#@]*)?(?:[/?#]|$)",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Command:
    """One normalized sub-command: the program plus its arguments."""

    name: str
    args: tuple[str, ...]
    raw: str
    # True when the sub-command was closed by a lone `&`.
    background: bool = False

    @property
    def program(self) -> str:
        """The name without a pinned version, so python3.11 reads as python."""
        return VERSION_SUFFIX.sub("", self.name) or self.name

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
    """A rule that stops a command, either outright or for confirmation.

    `names` selects the programs it applies to, or every program when empty;
    `predicate` narrows further.

    The two decisions have different readers, so their messages differ in
    kind. A `deny` message is read by the model: it says the block is a static
    setting rather than a live refusal, and names what to do instead. An `ask`
    message is read by the user in the approval prompt, which already shows the
    command, so it says only what the command itself does not -- the
    consequence -- in one sentence.
    """

    id: str
    names: frozenset[str]
    message: str
    predicate: Callable[[Command], bool] = field(default=lambda _: True)
    decision: str = "deny"

    def matches(self, command: Command) -> bool:
        if self.names and command.name not in self.names and command.program not in self.names:
            return False
        return self.predicate(command)


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

# The letter that hands an interpreter its program is not the same across the
# set, so one shared letter would miss whichever ones disagree. Keyed by the
# version-free name. deno is absent: it spells this as `deno eval`, not a flag.
INLINE_CODE_FLAG: dict[str, str] = {
    "python": "c",
    "node": "e",
    "ruby": "e",
    "perl": "e",
    "swift": "e",
    "bun": "e",
    "osascript": "e",
    "php": "r",
}

INTERPRETERS = frozenset(INLINE_CODE_FLAG)

REGISTRY_RUNNER_MESSAGE = (
    "Fetching a package from a registry and running it is blocked by a static "
    "rule in settings.json. Nobody blocked this interactively. Use a binary the "
    "project already depends on, or add the dependency explicitly first so the "
    "version is recorded. The sibling commands that only run what is already "
    "installed are still available: pnpm exec, yarn exec, bundle exec, "
    "composer exec, dotnet tool run."
)


# gh's global flags that take a separate value. Their value would otherwise
# read as the first subcommand word.
GH_VALUE_FLAGS = frozenset({"-R", "--repo", "--hostname", "-q", "--jq", "-t", "--template"})

GITHUB_HOST = re.compile(r"(?:^|\.)github\.com$", re.IGNORECASE)

# An argument that is itself a URL. Anchored, so a `://` inside a search query
# or a field value is left alone.
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
    # Asking gh how a subcommand works prints text and does nothing else, and
    # it is how the right invocation gets found in the first place.
    if "help" in set(command.long_flags()) or "-h" in command.args:
        return False

    words = gh_words(command)
    return any(words[: len(path)] == path for path in paths)


def gh_leaves_github(command: Command) -> bool:
    """True when `gh api` was pointed at a host that is not github.com."""
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
    # First, so that a command which also trips a later rule still gets the
    # run_in_background pointer: that is the fix the model has to reach for.
    Rule(
        id="background",
        names=frozenset(),
        predicate=lambda c: c.background,
        message=DETACH_MESSAGE,
    ),
    Rule(
        id="detach",
        names=frozenset({"nohup", "setsid", "disown"}),
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
        names=INTERPRETERS,
        predicate=lambda c: c.has_trailing_short_flag(INLINE_CODE_FLAG[c.program]),
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
    # Ask rules come last: the first match wins, so an overlapping deny has to
    # be reached first.
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
            "delete" in set(c.long_flags())
            or c.has_short_letter("d")
            or any(arg.startswith(":") and len(arg) > 1 for arg in c.positionals())
        ),
        message="This removes the branch from the remote.",
    ),
)


def shield(char: str) -> str:
    """The form a quoted or escaped character takes through the tokenizer."""
    return QUOTED_AMPERSAND if char == "&" else char


def strip_comments(command_line: str) -> str:
    """Drop `#` comments and shield quoted `&`, leaving other quoted text alone.

    Has to run before tokenizing: shlex removes the quotes, after which a
    quoted `#` cannot be told from a comment marker, nor a quoted `&` from the
    background operator. A `#` opens a comment only at the start of a word,
    which is what keeps flake refs and URL fragments.
    """
    result: list[str] = []
    quote = ""
    at_word_start = True
    index = 0

    while index < len(command_line):
        char = command_line[index]

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

        result.append(char)
        at_word_start = char.isspace() or char in ";|&()"
        index += 1

    return "".join(result)


def tokenize(command_line: str) -> list[str]:
    """Split a command line into shell tokens, keeping operators separate.

    Newlines and backticks become explicit separators first: shlex treats a
    newline as plain whitespace, which would splice two commands into one, and
    it has no notion of a backtick substitution at all.
    """
    without_comments = strip_comments(command_line)
    prepared = (
        without_comments.replace("\n", " ; ").replace("\r", " ; ").replace("`", " ; ")
    )

    lexer = shlex.shlex(prepared, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    # Comments are already gone, and shlex's own handling would take `#` in the
    # middle of a word too, eating nix flake refs and URL fragments.
    lexer.commenters = ""
    try:
        tokens = list(lexer)
    except ValueError:
        # Unbalanced quotes. Fall back to a crude split rather than skipping the
        # check, so a malformed command cannot be used to slip a rule.
        rough = re.sub(r"(\|\||&&|;|\||&|\(|\)|\{|\})", " \\1 ", prepared)
        tokens = [token.strip("\"'") for token in rough.split() if token.strip("\"'")]

    # Shielded ampersands stay shielded here: split_commands has yet to tell
    # the operators apart, and normalize restores them once it has.
    result: list[str] = []
    for token in tokens:
        result.extend(split_operators(token))
    return result


def split_operators(token: str) -> list[str]:
    """Break a spliced punctuation run such as `&)` into `&` and `)`.

    shlex groups adjacent punctuation into one token. Longest known operator
    first, so `&>` stays a redirect and does not become `&` plus `>`.
    """
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


def normalize(tokens: list[str], background: bool = False) -> Command | None:
    """Strip everything that only prefixes the real command."""
    tokens = [token.replace(QUOTED_AMPERSAND, "&") for token in tokens]

    changed = True
    while changed and tokens:
        changed = False

        while tokens and (tokens[0] in KEYWORDS or ASSIGNMENT.match(tokens[0])):
            tokens.pop(0)
            changed = True

        # `nix ... --command X ...` runs X; everything before it only picks an
        # environment. Dropping the prefix puts X in command position.
        if tokens and tokens[0] == "nix" and "--command" in tokens:
            del tokens[: tokens.index("--command") + 1]
            changed = True

        if tokens and tokens[0] in WRAPPERS:
            value_flags = WRAPPER_VALUE_FLAGS.get(tokens.pop(0), frozenset())
            changed = True
            # Some wrappers also carry a bare value, as `timeout 30` does.
            while tokens and (tokens[0].startswith("-") or DURATION.match(tokens[0])):
                flag = tokens.pop(0)
                if flag in value_flags and tokens and not tokens[0].startswith("-"):
                    tokens.pop(0)

    if not tokens:
        return None

    name = tokens[0]
    if "/" in name:
        name = name.rsplit("/", 1)[1]

    return Command(
        name=name, args=tuple(tokens[1:]), raw=" ".join(tokens), background=background
    )


def split_commands(command_line: str) -> list[Command]:
    commands: list[Command] = []
    current: list[str] = []

    for token in tokenize(command_line):
        if token in SEPARATORS:
            command = normalize(current, background=token == "&")
            if command:
                commands.append(command)
            current = []
        else:
            current.append(token)

    command = normalize(current)
    if command:
        commands.append(command)

    return commands


def nested_command(command: Command) -> str | None:
    """The program a shell was handed with -c, which no rule can otherwise see.

    The letter may sit anywhere in a short-flag cluster, and the program is the
    token after that cluster rather than the first positional, since a flag's
    own value can come in between.
    """
    if command.name not in SHELLS:
        return None

    for index, arg in enumerate(command.args):
        if not arg.startswith("-") or arg.startswith("--"):
            continue
        if "c" in arg[1:]:
            # An end-of-options separator may sit in between, and is not it.
            for candidate in command.args[index + 1 :]:
                if candidate != "--":
                    return candidate
            return None

    return None


def find_violation(command_line: str, depth: int = 0) -> tuple[Rule, Command] | None:
    for command in split_commands(command_line):
        for rule in RULES:
            if rule.matches(command):
                return rule, command

        # One level, deliberately. Deeper nesting stops being the plain detour
        # this hook exists to redirect, and containment is the sandbox's job.
        if depth == 0:
            payload = nested_command(command)
            if payload:
                inner = find_violation(payload, depth + 1)
                if inner:
                    return inner

    return None


def abbreviate(text: str, limit: int = ECHO_LIMIT) -> str:
    """Cut an over-long sub-command down to its head.

    The head is what identifies the call among several on one line, the only
    job the echo has. Nothing is kept from the end: the model wrote the
    command, so a trailing path tells it nothing it does not already have.

    Reserving the marker inside the limit makes two invariants exact: the
    result never exceeds `limit`, and so is never longer than what it replaced.
    """
    if len(text) <= limit:
        return text

    # len(text) has at least as many digits as the count of omitted characters,
    # so reserving against it can never come up short.
    marker_budget = len(f" ... (+{len(text)} chars)")
    head = text[: limit - marker_budget]
    return f"{head} ... (+{len(text) - len(head)} chars)"


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

    if rule.decision == "ask":
        # No echo: the prompt already shows the user the command.
        json.dump(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "ask",
                    "permissionDecisionReason": rule.message,
                }
            },
            sys.stdout,
        )
        return 0

    print(
        f"{rule.message}\n\nBlocked sub-command: {abbreviate(command.raw)}",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
