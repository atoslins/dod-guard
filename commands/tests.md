---
description: Audit test quality (not coverage). Invokes only the test-quality-auditor subagent. Useful after a TDD cycle.
---

# /dod:tests

After writing tests, this is the single-purpose check: "are these tests actually testing the production code?"

## What to do

1. Verify `.dod-guard.json` is present.
2. Run the deterministic scan first to catch the obvious cases:
   ```bash
   python3 "$CLAUDE_PLUGIN_ROOT/scripts/detect-test-tautology.py" . --diff --json
   ```
3. Dispatch the `test-quality-auditor` subagent via the Task tool. Tell it:
   - to write its JSON envelope to `.dod-guard/reports/tests-<timestamp>/test-quality-auditor.json`,
   - to focus on the current diff,
   - to consult the `${CLAUDE_PLUGIN_ROOT}/skills/stub-detection-patterns/SKILL.md` reference if needed.
4. Wait for completion. Read the agent's output JSON.
5. Render a short report:
   - one paragraph summary,
   - a bulleted list of issues with `file:line`,
   - the verdict on its own line.
6. If the verdict is FAIL, do NOT mark `.dod-guard/last-verify-passed` — even if `/dod:verify` would otherwise pass, a tests-failed audit blocks completion.

## Hard rules

- Do not invoke other subagents — this is the single-purpose lane.
- Do not write `.dod-guard/last-verify-passed` on PASS here — `/dod:verify` is what writes that marker. Passing tests-audit is necessary but not sufficient.
