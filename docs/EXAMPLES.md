# Examples

Three end-to-end scenarios showing exactly what the user types, what the plugin does, and what the orchestrator produces.

## Scenario 1 — New feature on a clean project

**Input:** "Add a `/login` endpoint that accepts `{email, password}` JSON and returns a token."

**What the plugin does:**

1. `SessionStart` hook detects `.dod-guard.json`. Injects the DoD context into the conversation: "DoD-Guard is active; expect to run `/dod:verify` before declaring done."
2. The orchestrator runs `/dod:checklist`. Sees seven items (including "tests added", "no new TODOs", "e2e probe").
3. The orchestrator writes `src/auth.ts`. The `PostToolUse` hook runs `detect-stubs.sh src/auth.ts`. Returns `count: 0`. Edit proceeds silently.
4. The orchestrator writes `tests/auth.test.ts`. `PostToolUse` runs detectors — also clean.
5. The orchestrator runs `/dod:verify`:

```
═════════════════════════════════════════════════════════════
DoD-Guard verify  (project: api-service, runner: jest)
═════════════════════════════════════════════════════════════
[1/5] Snapshot
  - branch:        feature/login-endpoint
  - HEAD:          3f4a2e1
  - dirty:         yes
  - changed files: 3

[2/5] Stubs & incomplete code
  - 0 stub-style issue(s)

[3/5] Tests
  - runner: jest
  - 24 passed, 0 failed, 0 skipped (4321 ms)

[4/5] E2E probe
  - curl -sSf -X POST http://localhost:3000/login -d '{"email":"a@b.c","password":"x"}'
  - exit_code: 0
  - evidence:  response contained {"token":"eyJ..."}

[5/5] Verdict
  ═══════════════════════════════════════════════════════════
  VERDICT: PASS
  ═══════════════════════════════════════════════════════════
```

6. The orchestrator emits the Task Completion Report. The `Stop` hook re-runs the pipeline, sees PASS, writes `.dod-guard/last-verify-passed`, exits 0. The orchestrator may now end the turn.

## Scenario 2 — Bug fix that introduces a regression

**Input:** "Fix the email validation regex — it rejects valid `+` addresses."

**What happens:**

1. The orchestrator edits `src/auth.ts:142`. `PostToolUse` runs `detect-stubs.sh` — clean.
2. The orchestrator runs `/dod:verify`. The deterministic phases pass, but the test suite shows `1 failed`:

```
[3/5] Tests
  - runner: jest
  - 23 passed, 1 failed, 0 skipped (4456 ms)
  - failures:
      AuthService › validateEmail › rejects pure-numeric local part

[5/5] Verdict
  VERDICT: FAIL
  Blocking reasons:
    - 1 test failed (existing test now fails after this change)
```

3. The orchestrator does NOT receive `last-verify-passed`. It investigates the failing test, sees the regex is now too permissive, narrows it, re-runs `/dod:verify`. PASS.
4. The orchestrator runs `/dod:audit`. The `regression-hunter` subagent compares against `.dod-guard/baseline.json` — passes are now 24/24 vs. baseline 24/24. `final-judge` PASS.
5. Done.

## Scenario 3 — Tempted to ship something half-done

**Input:** "Add a `/refund` endpoint. We'll wire up the payment gateway later."

**What the orchestrator is tempted to write:**

```ts
export async function refund(orderId: string): Promise<RefundResult | null> {
  // TODO: integrate with payment gateway
  return null;
}
```

**What the plugin does:**

1. `PostToolUse` runs `detect-stubs.sh src/refund.ts`. Returns `count: 2` (TODO marker + return null in an action-named function).
2. With `hooks.post_edit.severity = "block"` in `.dod-guard.json`, the hook emits `{"decision": "block", "reason": "DoD-Guard: 2 issue(s) detected in src/refund.ts after edit..."}`.
3. The orchestrator sees the block. It must remove the stub before continuing.
4. The honest path: implement the gateway call OR fail the request with `501 Not Implemented` AND test for the 501 response. Either way, the body is non-trivial.
5. The orchestrator runs `/dod:confess` before claiming done. The confession includes section 5 ("Files not wired up") and section 7 ("Refactors not done"). The `claim-validator` later checks each claim against the confession.

## Scenario 4 — Refactor (no behavior change)

**Input:** "Extract the auth middleware into its own module."

**Why this is special:** there is no new behavior to probe. `e2e-verifier` will mark the probe `not_applicable`.

**What happens:**

1. The orchestrator moves files. `PostToolUse` runs after each edit.
2. The `claim-validator` checks "extracted middleware to src/middleware/auth.ts" → runs `git diff --stat src/middleware/auth.ts` — file exists, content matches the old location. Agree.
3. `regression-hunter` sees the suite still passes (no test change expected). No regressions.
4. `e2e-verifier` reports `unverifiable: [{claim: "behavior unchanged", reason: "refactor with no behavior change; covered by passing tests"}]`. `final-judge` accepts this because the explanation is honest.
5. `/dod:audit` returns PASS.

## What goes wrong without DoD-Guard

For comparison, here is the same Scenario 3 without the plugin:

1. Orchestrator writes the stub.
2. Orchestrator writes a test that mocks the payment gateway and asserts `refund(orderId)` resolves to `null`.
3. Test suite passes.
4. Orchestrator declares "done."
5. The PR ships with a non-functional `/refund` endpoint. The bug surfaces when a real refund is requested in production.

DoD-Guard blocks at step 1 (stub detection) and step 4 (`Stop` hook refuses to release).
