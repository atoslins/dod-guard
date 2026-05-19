# Architecture

DoD-Guard composes five reinforcing layers. Each layer alone is bypassable; combined they make premature completion claims expensive.

## Layer diagram

```
                       ┌─────────────────────────────────────┐
                       │   Orchestrator (your Claude Code)   │
                       └──────────────┬──────────────────────┘
                                      │
                                      ▼
       ┌──────────────────────────────────────────────────────────────┐
       │  Layer 5: Skills                                             │
       │  dod-enforcement reprograms the orchestrator's "done" frame  │
       └──────────────┬───────────────────────────────────────────────┘
                      │
                      ▼
       ┌──────────────────────────────────────────────────────────────┐
       │  Layer 4: Slash commands                                     │
       │  /dod:init  /dod:verify  /dod:audit  /dod:confess  ...       │
       └──────────────┬───────────────────────────────────────────────┘
                      │
                      ▼
       ┌──────────────────────────────────────────────────────────────┐
       │  Layer 3: Subagents (read-only, adversarial)                 │
       │  completeness-auditor   test-quality-auditor   e2e-verifier  │
       │  regression-hunter      adversarial-reviewer   claim-valid.  │
       │                          └─ final-judge ─┘                   │
       └──────────────┬───────────────────────────────────────────────┘
                      │
                      ▼
       ┌──────────────────────────────────────────────────────────────┐
       │  Layer 2: Hooks (deterministic interception)                 │
       │  SessionStart    PostToolUse(Edit)    PostToolUse(Bash)      │
       │                          Stop              SubagentStop      │
       └──────────────┬───────────────────────────────────────────────┘
                      │
                      ▼
       ┌──────────────────────────────────────────────────────────────┐
       │  Layer 1: Detectors (no LLM)                                 │
       │  detect-stubs.sh   detect-empty-functions.py                 │
       │  detect-test-tautology.py    detect-suspicious-returns.py    │
       │  check-not-implemented.sh    coverage-delta.sh               │
       │  run-full-suite.sh           run-verification-pipeline.sh    │
       └──────────────────────────────────────────────────────────────┘
```

The lower the layer, the cheaper to execute and the harder to fool.

## Flow on "Claude declares done"

```
Claude ──┐
         ▼
  Stop hook fires (Layer 2)
         │
  reads .dod-guard.json
  reads transcript_path     ← detects whether any Write/Edit occurred this session
         │
  ┌──────┴──────┐
  │             │
no mutation   stop_hook_active=true   ──► exit 0 (loop prevention)
  │
  ▼
run-verification-pipeline.sh (Layer 1)
  ├── detect-stubs.sh
  ├── detect-empty-functions.py
  ├── detect-suspicious-returns.py
  ├── detect-test-tautology.py
  ├── check-not-implemented.sh
  └── run-full-suite.sh
         │
  ┌──────┴──────┐
  PASS         FAIL
  │             │
  write          {"decision":"block","reason": "<instructional message>"}
  .dod-guard/    │
  last-verify-passed
         │
  Claude is forced to continue working. /dod:verify is the recommended next step.
```

## Why each layer exists

| Layer | Stops what |
|-------|------------|
| Detectors | Stubs, TODOs, empty bodies, tautological tests, NotImpl markers |
| Hooks | Bypass attempts via Edit, git commit, declaring done before verifying |
| Subagents | Bugs that detectors miss; weak tests; unverified claims; regressions; e2e gaps; hostile review |
| Slash commands | Manual user-driven entry points; emergency rituals (`/dod:confess`) |
| Skills | Reframe the orchestrator's worldview when entering a DoD-guarded project |

## Independence and "one FAIL = FAIL"

Each subagent is dispatched as a fresh Task. They cannot see each other's reasoning, only the diff and the codebase. The `final-judge` then applies a strict rule:

```
verdict = PASS  ⟺  every auditor returned PASS
                   AND every PASS verdict had non-empty commands_run
```

Anything else is FAIL. There is no weighted voting, no "two out of three." This is by design: a flaky PASS hidden behind two real PASSes is exactly the kind of laundering this plugin is meant to prevent.

## Loop prevention

The `Stop` hook is the most delicate to write because the natural design — "re-block until verdict is PASS" — is also an infinite loop in the worst case. Claude Code injects `stop_hook_active: true` when the agent is in an active re-stop cycle; `stop-gate.sh` reads this flag and exits 0 to release the agent. The human can intervene from there.

## Files and where they live

- `.claude-plugin/plugin.json` — manifest read by Claude Code at install
- `hooks/hooks.json` — wires events to handler scripts
- `hooks/handlers/*.sh` — 5 hook handlers
- `scripts/*.{sh,py}` — 11 detector / aggregation scripts
- `agents/*.md` — 7 adversarial validators
- `commands/*.md` — 8 manual triggers
- `skills/*/SKILL.md` — 4 behavior shapers
- `templates/*.template` — used by `/dod:init`

Per-project state lives in `.dod-guard/` of the *consumer* repo, never inside the plugin.
