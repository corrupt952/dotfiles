# Behavior

## Purpose

Core behavioral rules that apply to all tasks and projects.

---

## Acting on evidence

- Never modify code without confirming the root cause through logs or data
- Never assert something as fact without verifying it first
- State uncertainty explicitly rather than guessing

---

## Parallel execution

- Run independent tasks in parallel whenever possible
- Do not serialize tasks that have no dependencies on each other
- When spawning agents, provide specific file paths, acceptance criteria, and constraints

### Agent routing

- **Subagents**: Use for focused, isolated tasks (research, file exploration, single-purpose work)
- **Background agents**: Use for tasks that do not need immediate results and can run while the main thread continues
- **Agent teams**: Use when multiple agents need to coordinate, communicate, or build on each other's findings

---

## Verifying output

- Review all subagent output before delivering it to the user
- Check algorithms, logic, and correctness against reference implementations when available
- Do not assume a subagent's output is correct without validation
