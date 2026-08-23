# Global Agent Rules

## Commit messages

- Follow explicit repository-local commit-message requirements first.
- When the repository does not specify a requirement, use Conventional Commits in the form `type: description`.
- Omit the scope by default. Use `type(scope): description` only when repository-local rules explicitly require a scope.
- Do not infer a scope solely from directory names or isolated historical commits.
- Write the subject in imperative mood ("add", not "added"), English, lowercase start, no trailing period, 50 characters or fewer.
- Give the subject exactly one verb and one object naming the thing changed, then stop. Enumerations ("X and Y") and purpose or method tails ("for X", "to improve Y", "with Z") belong in the body — they are also what breaks the character limit.
- Read `git diff --cached` and `git log --oneline -15` before drafting: the diff decides the type, and the recent log shows the conventions this repository already follows.
- Classify the type by effect, not by file extension, taking the first rule that matches:

  | # | Condition | Type |
  |---|-----------|------|
  | 1 | Only human-facing explanation changed (README, guides, code comments) | `docs` |
  | 2 | Only test files changed | `test` |
  | 3 | Only CI config changed | `ci` |
  | 4 | Behavior changes: new capability added | `feat` |
  | 5 | Behavior changes: defect corrected | `fix` |
  | 6 | Behavior-defining content changed, behavior equivalent | `refactor` |
  | 7 | None of the above (dependencies, tooling, build config, repo maintenance) | `chore` |

- Markdown is not automatically `docs`. Files that define behavior — `SKILL.md`, agent definitions, prompt templates — are source code, so they take rules 4 through 6. `docs` is only for content whose sole job is informing humans.
- Reach `chore` only after every rule above has been checked and none matched. Classify a mixed changeset by its dominant intent.

## Running work

- Record the request first, in the user's own words.
  - `TaskCreate` when available, otherwise `TODO.md` in the working directory; include the goal and what is out of scope.
  - Every piece of work traces to a recorded line; what the user has closed stays closed.
- A subagent brief names:
  - the agent (Agent `name`), an output file path and format, acceptance criteria;
  - what the other agents cover and what is out of scope; a model only when a cheaper one is enough;
  - the reporting lines: a one-line plan to `"main"` in the first tool round, one line per milestone, message-and-wait before anything outside the brief, results to a file with every `SendMessage` one line. The labee-standards hook adds them when missing.
- Steer as work lands.
  - Read each plan; confirm files by listing the directory; review against the brief before relaying.
  - Rework goes back to the same named reviewer.
- Report upward with what is outstanding, where it writes, and the decision it bears on; make the decisions that are yours.
- Edit source and Markdown with Read then Edit. Markdown is prose: one paragraph, one line.
- Produce only what was asked for: a plan exists once recorded, an artifact because it was requested, and a question the repository can answer itself is answered there first.
