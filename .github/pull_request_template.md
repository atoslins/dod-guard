<!-- Thanks for contributing to DoD-Guard! Fill out the sections below. -->

## What this PR does

<!-- One-paragraph summary. Mention which layer it touches: detectors,
     hooks, subagents, commands, skills, templates, docs. -->

## Why

<!-- The failure mode this catches, or the bug it fixes. Link an issue
     if there is one ("Closes #N"). -->

## Evidence

<!-- Paste the command outputs that prove the change works. -->

```
$ bash tests/test-detectors.sh
...

$ bash tests/test-hooks.sh
...

$ bash tests/test-agents-syntax.sh
...

$ bash tests/test-integration.sh
...

$ shellcheck -x hooks/handlers/*.sh scripts/*.sh tests/*.sh
(empty)

$ claude plugin validate .
✔ Validation passed

$ bash scripts/run-verification-pipeline.sh --skip-tests --json | jq .verdict
"PASS"
```

## DoD-Guard self-checklist

- [ ] No `pass` / `return None` / `return null` / `{}` stubs introduced.
- [ ] No `TODO` / `FIXME` left in modified files (use an issue instead).
- [ ] New behavior covered by a real test (not `expect(x).toBeDefined()`).
- [ ] If a hook or detector changed, `shellcheck -x` is clean.
- [ ] If JSON output changed, the consumer in `run-verification-pipeline.sh` and the relevant subagent prompts still parse it.
- [ ] CHANGELOG entry added under `[Unreleased]`.
- [ ] Self-audit (`run-verification-pipeline.sh --skip-tests`) still reports `PASS`.

## Screenshots / output

<!-- For UX-visible changes (slash command output, /dod:verify report format),
     paste a before/after. -->
