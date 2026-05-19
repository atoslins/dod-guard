---
description: Fast scan for stubs / TODOs / empty functions across the whole project. No tests, no subagents.
argument-hint: "[--all|--diff]"
---

# /dod:stubs

The fastest sanity check. Useful while you're working, not just at the end.

## What to do

1. If `.dod-guard.json` is absent, still proceed — this command is useful even before init.
2. Decide the scope:
   - `--diff` (default if there is a non-empty staged or working diff): scan only files in the current diff.
   - `--all`: scan the entire project.
3. Run:
   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/scripts/detect-stubs.sh" $SCOPE --json > /tmp/dodg-stubs.json
   python3 "$CLAUDE_PLUGIN_ROOT/scripts/detect-empty-functions.py" . --json > /tmp/dodg-empty.json
   bash "$CLAUDE_PLUGIN_ROOT/scripts/check-not-implemented.sh" . --json > /tmp/dodg-ni.json
   ```
4. Merge the three JSON outputs and print the issues table:
   ```
   SEVERITY  FILE:LINE                    TYPE              EVIDENCE
   high      src/auth.ts:42               todo_marker       // TODO: validate signature
   high      src/auth.ts:88               empty_function    function refresh() {}
   ```
5. Print the totals on the last line: `Total: <high> high, <warn> warn`.

## Hard rules

- Do not edit anything. This is informational.
- Do not run the test suite — the user wants speed.
- Exit with code 0 if there are zero high-severity issues, else 1, so it can be chained in shell scripts.
