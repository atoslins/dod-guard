---
description: Present the project's Definition of Done checklist (from DOD.md) with the items completed this session marked off.
---

# /dod:checklist

Render the project's DoD as an actionable checklist with this session's progress overlaid.

## What to do

1. Read `DOD.md` from the project root. If absent, suggest `/dod:init` and stop.
2. Parse it as markdown. The checklist items are `- [ ] ...` or `- [x] ...` entries (you treat both as un-completed for this run — the session-state is the source of truth, not the file).
3. Build a "session state":
   - From the transcript, look for evidence of each checklist item being satisfied. Heuristics:
     - "All public functions have docstrings" → run a quick grep for `def ` vs. presence of `"""` in the same file.
     - "Tests cover the new feature" → check for new test files in the staged diff.
     - "No new TODOs" → run `bash "$CLAUDE_PLUGIN_ROOT/scripts/detect-todos.sh" --json` and check for zero count.
   - For each item that cannot be auto-verified, leave it unchecked and add a "(needs manual review)" note.
4. Render the checklist:
   ```
   ## Definition of Done — <project-name>
   
   - [x] All public functions have docstrings
   - [ ] Tests cover the new feature  (needs manual review)
   - [x] No new TODOs added
   - [ ] ...
   ```
5. At the bottom, summarize: `N of M items satisfied (auto-verified)`.
6. If `N == M`, suggest running `/dod:verify` to confirm the full deterministic chain.

## Hard rules

- Never write to `DOD.md` from this command. It is read-only.
- Never invent items that are not in `DOD.md` — the project's checklist is the source of truth.
- Auto-check only when the evidence is concrete. When in doubt, leave unchecked.
