---
name: evidence-reporting
description: Use when producing any DoD-Guard report — task completion reports from the orchestrator, validator envelopes from subagents, /dod:confess output. Specifies the "command run block" format, citation style, and structural rules.
---

# Evidence-Reporting

A report without evidence is a vibe. This skill defines the canonical formats so reports across DoD-Guard remain comparable and tamper-evident.

## The Command Run Block

Whenever you ran a command whose output supports your claim, present it as a block:

````markdown
```bash
$ git rev-parse HEAD
b06e407
```
````

Rules:

- Always include the `$` prompt to make the command itself easy to copy.
- Output may be truncated, but cite the truncation (`(... 200 lines elided ...)`).
- Do not paraphrase the output. Copy it verbatim. If you must summarize, do so *under* the block.

## Citing files

Every claim about a file uses `path:line` format. Avoid `path` without a line — it forces the reader to grep. Examples:

- ✅ `src/auth.ts:42 — added validate_signature()`
- ✅ `tests/test_user.py:88-104 — covers the empty-password case`
- ❌ `auth.ts — modified` (which line? what changed?)

When the change is multi-line, use the range form. When the relevant evidence is across multiple files, list each on its own line.

## The Task Completion Report template

The orchestrator's completion report MUST match this template. The `claim-validator` agent grades each section:

```markdown
## Task Completion Report

### Summary
<1 paragraph, plain language>

### Files modified
- <path:line-range>  <one-line description>

### Claims I am making
For each atomic claim:
- Claim: <verb-led sentence — "added X", "fixed Y", "tests now cover Z">
  Evidence: <a path:line, or a command run block, or both>

### Verification I ran
- /dod:verify     — verdict: PASS | FAIL
- /dod:audit      — verdict: PASS | FAIL | "not run"
- Manual probe:   <verbatim command + 1-line result>

### Known limitations
- <gap with a file path, or "(none)">

### What the next session should pick up
- <follow-up, or "(none)">
```

Refusal to include a section is a FAIL. "(none)" is acceptable; missing is not.

## The Confession template (for `/dod:confess`)

Saved to `.dod-guard/reports/confession-<timestamp>.md`. The seven sections are mandatory:

1. **Gaps in the implementation** — what is incomplete vs. promised.
2. **Weak or decorative tests** — assertions that prove nothing.
3. **Edge cases not handled** — boundary inputs not tested.
4. **Hardcoded or placeholder values** — magic numbers, URLs, secrets in source.
5. **Files not wired up** — dead code, unimported modules.
6. **TODOs / FIXMEs left behind** — every marker in your diff.
7. **Refactors you wanted to do but didn't** — the most-skipped section.

For each section that is genuinely empty, write `(nothing to confess in this section)` — not `n/a`, not skipped.

## The Subagent JSON envelope

Validators emit a single JSON object. See [[adversarial-verification]] for the schema. The hard rules are:

- One JSON document on stdout, nothing else.
- `verdict` is exactly `"PASS"` or `"FAIL"`.
- `commands_run` is required and non-empty for any PASS.
- File paths are repo-relative. Line numbers are 1-based.

## When you cannot produce evidence

Be explicit:

- For an orchestrator claim that lacks evidence in this environment: list it under "Verification I ran" with `"manual probe: not applicable in this environment; verified by <how, by whom>"`. Do not silently omit.
- For a subagent finding that you cannot probe: include it under `notes` and downgrade your verdict to FAIL with reason "could not verify <thing>."

See also: [[dod-enforcement]], [[adversarial-verification]].
