from pathlib import Path
import sys
import tomllib

PLATFORM = "macos-arm64"


def configured_version(name: str, spec) -> str:
    if isinstance(spec, str):
        return spec
    if isinstance(spec, dict) and isinstance(spec.get("version"), str):
        return spec["version"]
    raise ValueError(f"{name}: expected a version string or a table with one")


def check(config_path: Path, lock_path: Path) -> list[str]:
    config = tomllib.loads(config_path.read_text(encoding="utf-8"))
    lock = tomllib.loads(lock_path.read_text(encoding="utf-8"))
    tools = config.get("tools", {})
    locked = lock.get("tools", {})
    problems = []

    for name, spec in tools.items():
        try:
            version = configured_version(name, spec)
        except ValueError as error:
            problems.append(str(error))
            continue
        entries = [entry for entry in locked.get(name, []) if entry.get("version") == version]
        if not entries:
            problems.append(f"{name}: {version} is not locked")
            continue
        platform = entries[0].get(f"platforms.{PLATFORM}", {})
        if not platform.get("checksum"):
            problems.append(f"{name}: {version} has no {PLATFORM} checksum")

    for name in locked:
        if name not in tools:
            problems.append(f"{name}: locked but not configured")

    return problems


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {argv[0]} CONFIG LOCK", file=sys.stderr)
        return 2
    problems = check(Path(argv[1]), Path(argv[2]))
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
