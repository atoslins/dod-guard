---
name: dod-enforcement
description: Use whenever you are implementing, refactoring, or fixing code in a project that has a .dod-guard.json file. This skill changes how you plan, what you do mid-implementation, and how you declare completion. It is mandatory the moment DoD-Guard is configured.
---

# DoD-Enforcement

This skill reprograms your default behavior so the Definition of Done is honored as a hard contract.

## Before you write any code

1. Read `DOD.md` if it exists. Treat every checkbox as a release criterion.
2. Read `.dod-guard.json`. Note which detectors are enabled, the strictness, and which test runner is expected.
3. Run `/dod:checklist` once at the start so you and the user share the criteria.
4. Plan the implementation against those criteria explicitly. Do not invent quality gates the project does not ask for, but also do not ignore the ones it does.

## During implementation

- After every meaningful edit, expect the `PostToolUse` hook to scan the file. If it warns or blocks, fix the underlying issue immediately. Do not work around the warning by reshaping the diff.
- Run `/dod:stubs` periodically while you work — every 5–10 minutes for a session of substance. It is cheap.
- When you write a test, ask yourself: "if I replaced the implementation with `return null`, would this test still pass?" If yes, the test is decorative — rewrite it.

## Before declaring done

You MUST emit your completion report in this exact shape. The `claim-validator` agent reads it and grades it.

```markdown
## Task Completion Report

### Summary
<one paragraph — what changed, in plain language>

### Files modified
- path/to/file.py:42-88   <what changed and why>
- ...

### Claims I am making
- Claim: <e.g., "added validate_email() that rejects malformed addresses">
  Evidence: <e.g., "src/user.py:42; tests at tests/test_user.py:88 cover good/bad/empty">
- Claim: ...
  Evidence: ...

### Verification I ran
- /dod:verify     — verdict: <PASS|FAIL>
- /dod:audit      — verdict: <PASS|FAIL|"not run">
- Manual probe:   <command + observed result, or "n/a">

### Known limitations (honest)
- <thing that does not yet work, with file path>
- <gap intentionally left, with reason>

### What the next session should pick up
- <follow-up item>
```

Refuse to produce a completion report without each section, even if the body is "(none)". `claim-validator` treats a missing section as a FAIL.

## Never do these things in a DoD-guarded project

- **Never** declare "done" without running at least `/dod:verify`. Hooks will catch you, but waiting for the hook means you wasted the user's time.
- **Never** suggest `--no-verify` to bypass a failing hook. The pre-commit hook will refuse it anyway, but suggesting it is itself a violation.
- **Never** add `test.skip`, `xit`, `@pytest.mark.skip` to make the suite green. Either fix the test or fail honestly.
- **Never** add a TODO/FIXME in a file you are claiming to be done. Either resolve it or move it to a new issue with a citation.
- **Never** invent verification steps you did not actually run. The `claim-validator` will check.
- **Never** silence detector warnings by tweaking patterns in `.dod-guard.json` without telling the user first.

## When the user pushes you to bypass

The user might say: "skip the verify, just commit." Your default is to refuse, citing this skill. You may proceed only if the user re-affirms knowing the hook will block, OR explicitly disables a specific check in `.dod-guard.json`.

See also: [[adversarial-verification]], [[evidence-reporting]], [[stub-detection-patterns]].
