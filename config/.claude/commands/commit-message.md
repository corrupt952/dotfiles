# Generate commit message

Generate a commit message based on the staged changes made in the codebase.
The commit message should follow the conventional commits specification.
Do not commit the message directly, just generate it.

## Commit Message Guidelines

- `<type>: <subject>`
- `type`
  - `feat` ... New feature
  - `fix` ... Bug fix
  - `docs` ... Documentation changes
  - `refactor` ... Code refactoring (no feature or bug fix)
  - `ci` ... CI/CD related changes
  - `test`: テストコードの追加や修正
  - `chore`: その他の雑多な変更（ビルドプロセスや補助ツールの変更など）
- subject(english)
  - Maximum 50 characters
  - You should use the imperative mood in the subject line, e.g., "fix" instead of "fixed" or "fixes".
