---
description: Full multi-agent audit. Invokes the 7 adversarial subagents and aggregates their verdicts via final-judge. ~2-3 minutes.
argument-hint: "[--parallel|--sequential]"
---

# /dod:audit

The deep audit. Use before merging substantial changes, after a long implementation session, or when `/dod:verify` keeps reporting PASS but you suspect the orchestrator is hiding something.

## What to do

1. Confirm `.dod-guard.json` is present. Refuse to run otherwise (suggest `/dod:init`).
2. Read `.dod-guard.json` for the `audit.parallel` setting (default: true). The CLI flag overrides.
3. Generate or reuse a session ID:
   ```bash
   session_id="audit-$(date -u +%Y%m%dT%H%M%SZ)"
   mkdir -p ".dod-guard/reports/$session_id"
   ```
4. Dispatch the six original auditors (use the Task tool):
   - `completeness-auditor`
   - `test-quality-auditor`
   - `e2e-verifier`
   - `regression-hunter`
   - `adversarial-reviewer`
   - `claim-validator`

   Each subagent must be told to write its JSON envelope to `.dod-guard/reports/$session_id/<agent-name>.json`. In parallel mode, dispatch all six in a single message with multiple Task tool blocks.
5. Wait for all six to complete. The SubagentStop hook will also have recorded each output as a side effect — that is by design and acts as a backup.
6. Dispatch the seventh agent: `final-judge`. Pass it `$session_id` as input and tell it to read every JSON in `.dod-guard/reports/$session_id/`.
7. Print the `final-judge`'s `summary_for_human` verbatim. Append a footer:

   ```
   ───────────────────────────────────────────
   Audit complete. Session: <session_id>
   Report dir: .dod-guard/reports/<session_id>/
   Final verdict: PASS | FAIL
   ───────────────────────────────────────────
   ```

## Verdict-handling rules

- If `final-judge` returns FAIL, do not write `.dod-guard/last-verify-passed`. The user must fix and re-run.
- If `final-judge` returns PASS, write the marker (same one `/dod:verify` writes).
- Never override the `final-judge`'s decision.

## Hard rules

- The 7 subagent dispatches are not optional — even auditors you "think" will pass MUST be run. The point is independence.
- If any subagent fails to produce a JSON envelope, treat that agent as FAIL and let `final-judge` see the missing report.
- Do not edit files at any point during the audit.
