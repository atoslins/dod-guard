---
description: Quick 5-phase deterministic verification (snapshot → stubs → tests → e2e probe → verdict). Writes .dod-guard/last-verify-passed on PASS.
---

# /dod:verify

Fast verification path. No LLM-heavy subagents, no parallel orchestration — this should complete in 30 seconds for a small project. Use this often. Use `/dod:audit` only when you want the full multi-agent audit.

## Required output format

You MUST emit the report in this exact shape (the header rule and the section
separators are mandatory — they make the output greppable in transcripts):

```
═════════════════════════════════════════════════════════════
DoD-Guard verify  (project: <name>, runner: <runner>)
═════════════════════════════════════════════════════════════
[1/5] Snapshot
  - branch:        <git branch>
  - HEAD:          <short sha>
  - dirty:         <yes|no>
  - changed files: <N>

[2/5] Stubs & incomplete code
  - <count> stub-style issue(s)
  <bulleted list if any>

[3/5] Tests
  - runner: <pytest|jest|vitest|go|cargo|none>
  - <passed> passed, <failed> failed, <skipped> skipped (<duration_ms> ms)
  <failures listed if any>

[4/5] E2E probe
  - <chosen probe or "no probe applicable in this environment">
  - exit_code: <n>
  - evidence:  <one line>

[5/5] Verdict
  ═══════════════════════════════════════════════════════════
  VERDICT: PASS | FAIL
  ═══════════════════════════════════════════════════════════
  <if FAIL: blocking reasons, ordered by severity>
```

## What to do

1. Bail with a clear message if `.dod-guard.json` is missing.
2. **Phase 1 — Snapshot**: run `git status --porcelain`, `git rev-parse --short HEAD`, `git diff --name-only`.
3. **Phase 2 — Stubs**: run `bash "$CLAUDE_PLUGIN_ROOT/scripts/detect-stubs.sh" --all --json` and `python3 "$CLAUDE_PLUGIN_ROOT/scripts/detect-empty-functions.py" . --json`. Aggregate.
4. **Phase 3 — Tests**: run `bash "$CLAUDE_PLUGIN_ROOT/scripts/run-full-suite.sh" --quiet`.
5. **Phase 4 — E2E probe**: pick the cheapest reproducible probe (curl an endpoint, run the CLI, `python3 -c "..."`). If none is reproducible from the current environment, say so and mark as `not_applicable`.
6. **Phase 5 — Verdict**: PASS only if every phase reports zero blocking issues. Otherwise FAIL with a concise list.
7. On PASS:
   - Write the current Unix timestamp to `.dod-guard/last-verify-passed`.
   - Print "Verify marker refreshed; you can now `git commit` within the TTL."
8. On FAIL:
   - Do NOT write the marker.
   - Print a one-line summary, then the ordered fix list.

## Hard rules

- Never claim PASS without running phases 2 and 3.
- Never silently skip the e2e probe — either run something or label it `not_applicable` with a reason.
- Do not run subagents from this command; that is `/dod:audit`.
