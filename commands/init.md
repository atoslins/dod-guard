---
description: Initialize DoD-Guard in the current project (creates .dod-guard.json + DOD.md + .dod-guard/ dir).
argument-hint: "[--strict|--lenient]"
---

# /dod:init

Bootstrap DoD-Guard for the current project. Idempotent: re-running updates the stack-specific defaults but never overwrites a customized `DOD.md` without confirmation.

## What to do

1. Detect the project stack by checking, in order:
   - `pyproject.toml` or `setup.cfg` or `requirements.txt` → **python**
   - `package.json` → inspect dependencies for `jest`, `vitest`, `mocha` → **node** (jest | vitest | mocha | npm-test)
   - `go.mod` → **go**
   - `Cargo.toml` → **rust**
   - none of the above → **generic** (still proceed)
2. Read `${CLAUDE_PLUGIN_ROOT}/templates/dod-guard.json.template` and substitute the placeholders:
   - `{{STACK}}` → the detected stack
   - `{{TEST_RUNNER}}` → the matching runner from above (e.g., `pytest`, `jest`, `vitest`, `go-test`, `cargo-test`, `none`)
   - `{{STRICTNESS}}` → `strict` if the user passed `--strict`, `lenient` if `--lenient`, otherwise `normal`
   Write the result to `.dod-guard.json` in the project root. If a file already exists, diff it against the template and apply only the missing keys (preserve user-customized values).
3. Read `${CLAUDE_PLUGIN_ROOT}/templates/DOD.md.template` and write it to `DOD.md`. If `DOD.md` already exists, **do not overwrite** — instead, print a diff against the template and ask the user whether to merge.
4. Create the directory `.dod-guard/` and inside it `reports/` (with a `.gitkeep`).
5. Append a single line to `.gitignore` if it does not already include `.dod-guard/reports/`:
   ```
   .dod-guard/reports/
   .dod-guard/last-verify-passed
   ```
6. Read `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE-dod-section.md`. Print it and ask the user whether to append it to the project's `CLAUDE.md` (do not auto-append — many projects don't yet have one).
7. Print a final summary:
   - detected stack and runner
   - files created/updated
   - next steps: `/dod:checklist`, `/dod:verify`

## Stop conditions

- If `.dod-guard.json` exists AND the user did not pass any flag, ask "DoD-Guard is already initialized in this project. Refresh defaults? [y/N]". Do not silently overwrite.
- If the stack is `generic`, warn the user that detector coverage will be limited and recommend they add patterns under `detectors.stubs.patterns` in `.dod-guard.json`.
