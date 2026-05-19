# Definition of Done — {{PROJECT_NAME}}

This file lists the criteria that any change to this project must satisfy before it can be called "done." Edit it to match the project's actual standards. The `DoD-Guard` plugin reads this file and surfaces unmet items via `/dod:checklist`.

## Universal criteria (apply to every change)

- [ ] All new public functions have a docstring or JSDoc/Godoc comment explaining their contract.
- [ ] No new TODO / FIXME / XXX / HACK markers introduced (use issues, not comments, for follow-ups).
- [ ] No function ships with a stub body (`pass`, `return None`, `return null`, `{}`, `todo!()`, `unimplemented!()`).
- [ ] Tests added for new code paths. Assertions exercise real behavior — no `expect(x).toBeDefined()`-style decorative tests.
- [ ] No existing test was deleted, skipped, or `xit`-ed to make the suite green.
- [ ] Test suite passes locally on the current platform.
- [ ] Manual or automated end-to-end probe of the new behavior succeeded (paste the command + result in the PR description).
- [ ] Files created are wired into the rest of the project (imported, registered, exported as appropriate).
- [ ] Configuration is in config files, not hardcoded in source.
- [ ] Secrets and API keys are not committed in plaintext.
- [ ] Documentation that mentions the changed behavior is updated.

## Project-specific criteria

<!-- Add items below that are specific to this codebase. Examples: -->
<!-- - [ ] Migrations are reversible. -->
<!-- - [ ] New gRPC methods are added to both client and server packages. -->
<!-- - [ ] OpenAPI spec is regenerated. -->
<!-- - [ ] Telemetry events follow the naming convention in docs/telemetry.md. -->

- [ ] _(replace this placeholder with a real project-specific criterion)_

## What "verified" means in this project

For each criterion above, the check is satisfied only when there is concrete evidence:

- "Tests pass" requires the exact command + exit code, not a vibe check.
- "End-to-end probe" requires a curl/CLI invocation with the response body, or a test that calls the same interface a user would.
- "Documentation updated" requires the diff to include the doc change in the same PR.

## How to use this file

Run `/dod:checklist` to see which items have been auto-verified in the current session and which still need manual confirmation. The orchestrator will not declare "done" while any blocking item is unresolved.
