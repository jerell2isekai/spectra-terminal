# Sample AGENTS.md file

## Dev environment tips
- Use `rg`, `fd`, or repo-aware tools to locate the right package or module before editing.
- Confirm the actual package, app, or target name from the nearest manifest/config file instead of assuming from the workspace root.
- Prefer the smallest local setup command that makes lint, typecheck, and tests work for the target project.
- Read existing project instructions and conventions before introducing a new pattern.

## Testing instructions
- Find the CI or local verification flow from `.github/workflows`, `package.json`, `Makefile`, or equivalent project files.
- Run the narrowest relevant checks first, then rerun the minimum necessary full validation before finishing.
- Fix failing tests, lint errors, and type errors before proposing completion.
- Add or update tests when the change modifies behavior, even if nobody explicitly asked.
- After refactors or file moves, rerun lint/typecheck to catch stale imports and config regressions.

## PR instructions
- Summarize the user-visible change and the concrete verification performed.
- Keep commits and PR scope focused; do not mix unrelated cleanup.
- Call out any follow-up risk, migration step, or manual validation still needed.
- If the repo has a PR title convention, follow it exactly.
