---
description: Generate a human-readable markdown report of DoD state from existing .dod-guard/reports/ — no subagents, just formatting.
argument-hint: "[<session-id>]"
---

# /dod:report

Read what is already on disk and present it. Cheap, no LLM dispatch.

## What to do

1. Resolve the target session:
   - If the user passes a session ID, use it.
   - Otherwise, pick the most recent directory under `.dod-guard/reports/` (lexicographic; our session IDs are ISO-8601 timestamps so this is also chronological).
2. Read every JSON file in that directory.
3. Render a markdown report with these sections, in order:
   - **Header**: project name (from `package.json` / `pyproject.toml` / cwd basename), session ID, generated_at.
   - **Verdict at a glance**: a table with each auditor's name and verdict (PASS/FAIL/missing).
   - **Blocking issues**: ordered by severity, grouped by file. Cite file:line.
   - **Warnings**: same shape but lower severity.
   - **Unverifiable claims** (from `claim-validator`): list verbatim.
   - **Coverage**: latest from `regression-hunter` (or "n/a").
   - **What to fix next**: an actionable checklist derived from blocking issues.
   - **Footer**: link to the raw JSON files for each auditor.
4. Print the rendered markdown to stdout. Do not write it to a file unless the user asks.

## Hard rules

- Do not run subagents. This command is read-only over `.dod-guard/reports/`.
- Do not paraphrase auditor findings beyond shortening for the human summary — keep the source citations exact.
- If a report file is malformed, surface that in the table (`<auditor>: malformed report`) instead of silently dropping it.
