# Sample CLAUDE.md file

## Working style
- Read the local project instructions and existing code patterns before making changes.
- Prefer the simplest implementation that solves the verified problem.
- Keep changes scoped; avoid incidental refactors unless they are required for correctness.
- Surface assumptions, blockers, and verification gaps explicitly instead of guessing.

## Verification expectations
- Run the minimum relevant build, lint, test, or runtime check for the files you touched.
- If a broader check is too expensive, explain what was run and what remains unverified.
- Re-run the affected checks after fixing an issue instead of assuming the repair worked.

## Delivery expectations
- Report concrete file paths, behavior changes, and verification results.
- Mention breaking risk, follow-up work, and any manual testing still required.
- Do not mark work complete if key validation is still missing.
