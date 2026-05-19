<div align="center">

# DoD-Guard

### Definition of Done as an executable barrier for Claude Code

*Stops AI agents (and humans) from declaring tasks **done** while the code is still half-baked.*

[![GitHub release](https://img.shields.io/github/v/release/atoslins/dod-guard?include_prereleases&label=release)](https://github.com/atoslins/dod-guard/releases)
[![claude-code](https://img.shields.io/badge/claude--code-%E2%89%A5%202.1-blue)](https://docs.anthropic.com/claude-code)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![python](https://img.shields.io/badge/python-%E2%89%A5%203.10-blue)](https://www.python.org/)
[![bash](https://img.shields.io/badge/bash-%E2%89%A5%204.0-blue)](https://www.gnu.org/software/bash/)
[![tests](https://img.shields.io/badge/tests-94%20passing-brightgreen)](tests/)
[![shellcheck](https://img.shields.io/badge/shellcheck-clean-brightgreen)](https://www.shellcheck.net/)

</div>

---

```text
═════════════════════════════════════════════════════════════
DoD-Guard verify  (project: my-api, runner: jest)
═════════════════════════════════════════════════════════════
[1/5] Snapshot          branch=feature/refund  HEAD=3f4a2e1  dirty=yes
[2/5] Stubs             ✘ 2 issue(s):
  - high  src/refund.ts:14    todo_marker: // TODO: integrate gateway
  - high  src/refund.ts:18    empty_function: refund() returns null
[3/5] Tests             24 passed, 0 failed (4.3s)
[4/5] E2E probe         not_applicable — no live server
[5/5] Verdict           ═══════════════════════════════════════
                        VERDICT: FAIL
                        ═══════════════════════════════════════
                        Fix the 2 stubs and re-run /dod:verify.
```

---

## Why this exists

LLM-driven coding assistants are wired to declare "done." The failure modes are everywhere:

- A function ships as `pass` / `return None` / `TODO: implement`.
- A test asserts `expect(x).toBeDefined()` — it proves the function exists, not that it works.
- A summary claims "tests pass" while three tests were silently `.skip`-ed.
- An end-to-end behavior is announced without a single command being run.
- A confident final report has zero supporting evidence.

DoD-Guard turns the **Definition of Done** from a prompt into a wall the agent cannot talk past. Hooks block at the source of every shortcut. Read-only adversarial subagents audit the orchestrator from the outside. The `Stop` hook refuses to release the turn while the DoD is unmet — with proper `stop_hook_active` loop prevention.

---

## How it works

Five reinforcing layers, ordered by cost-to-execute (cheapest first):

```
┌──────────────────────────────────────────────────────────────┐
│  L5  Skills            reframe how the orchestrator plans    │
│  L4  Slash commands    /dod:verify  /dod:audit  /dod:confess │
│  L3  Subagents         7 adversarial validators (read-only)  │
│  L2  Hooks             SessionStart · PostToolUse · Stop     │
│  L1  Detectors         bash + python — milliseconds, no LLM  │
└──────────────────────────────────────────────────────────────┘
```

| Layer | What it stops |
|-------|----------------|
| **Detectors** | Stubs, TODOs, empty bodies, tautological tests, NotImpl markers |
| **Hooks** | Bypass attempts via edit, commit, declaring done before verifying |
| **Subagents** | Bugs detectors miss; weak tests; unverified claims; regressions; e2e gaps |
| **Slash commands** | Manual entry points; emergency rituals (`/dod:confess`) |
| **Skills** | Reframe the orchestrator's worldview when entering a DoD-guarded project |

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the layer diagram and the full flow on "Claude declares done."

---

## Install

Inside any Claude Code session:

```bash
/plugin marketplace add https://github.com/atoslins/dod-guard
/plugin install dod-guard@dod-guard-local
/reload-plugins
```

To develop locally:

```bash
git clone https://github.com/atoslins/dod-guard
/plugin marketplace add /absolute/path/to/dod-guard
/plugin install dod-guard@dod-guard-local
/reload-plugins
```

---

## First-run

Inside any project you want to guard:

```bash
/dod:init                # detects stack (Node / Python / Go / Rust), writes config + DOD.md
/dod:checklist           # shows the Definition of Done
/dod:verify              # 30-second deterministic check
```

That's it. From that point on, hooks fire automatically on every edit, every commit attempt, and every turn-end. If the orchestrator tries to declare "done" with a stub in the diff, the `Stop` hook returns:

```json
{"decision": "block",
 "reason": "DoD-Guard: cannot end the turn — Definition of Done is unmet.
            Run /dod:verify to see the full list of blocking issues."}
```

---

## The commands

| Command | Purpose | Time |
|---------|---------|------|
| **`/dod:init`** | Bootstrap config and DoD checklist for the project | < 5 s |
| **`/dod:verify`** | Fast 5-phase deterministic check; refreshes the marker | ~ 30 s |
| **`/dod:audit`** | Full multi-agent audit (7 subagents in parallel) | 2-3 min |
| **`/dod:report`** | Read existing reports, format markdown — no LLM | < 1 s |
| **`/dod:stubs`** | Fastest scan: stubs and TODOs only | ~ 2 s |
| **`/dod:tests`** | Audit only test quality (post-TDD) | ~ 30 s |
| **`/dod:checklist`** | Show DoD with this session's auto-verified items | < 5 s |
| **`/dod:confess`** | Force a 7-section paranoid self-audit | ~ 10 s |

---

## What gets caught

### Cross-language (Python / JS / TS / Go / Rust / Ruby / Bash)

| Pattern | Detector |
|---------|----------|
| `pass` · `...` · `return None` · `{}` as function body | `detect-empty-functions.py` (AST for Python) |
| `TODO` · `FIXME` · `XXX` · `HACK` markers | `detect-stubs.sh` + `detect-todos.sh --diff` |
| `NotImplementedError` · `todo!()` · `unimplemented!()` · `panic("not implemented")` | `check-not-implemented.sh` |
| Action-named fns returning only `null` / `{}` / `[]` | `detect-suspicious-returns.py` |

### JavaScript / TypeScript-specific

| Pattern | Detector |
|---------|----------|
| `expect(x).toBeDefined()` / `.not.toBeNull()` / `.toBeTruthy()` on a literal | `detect-test-tautology.py` |
| `expect(mock).toHaveBeenCalled()` with no matching `.toHaveBeenCalledWith(...)` | `detect-test-tautology.py` |
| `expect.assertions(0)` · `expect({}).toMatchSnapshot()` | `detect-test-tautology.py` |
| `assert.ok(true)` · `.to.be.ok` · `.to.exist` (Node / chai weak) | `detect-test-tautology.py` |
| `test.skip` / `xit` / `xdescribe` added in this diff | `detect-test-tautology.py` |

### Go-specific

| Pattern | Detector |
|---------|----------|
| `func NewX() *X { return &X{} }` (constructor with no fields set) | `detect-suspicious-returns.py` |
| `_ = err` · `_, _ = ...` (error-swallow) | `detect-suspicious-returns.py` |
| `assert.True(t, true)` · `assert.Equal(t, x, x)` · `assert.NoError(t, nil)` | `detect-test-tautology.py` |
| `TestX(t *testing.T)` body with no assertion-like call | `detect-test-tautology.py` |
| `t.Skip(...)` · `t.Log("TODO...")` | `detect-test-tautology.py` |
| `// nolint:` added in the diff | `detect-stubs.sh` · `detect-todos.sh` |

### Multi-agent verification

| Audit | Subagent |
|-------|----------|
| Bugs, edge cases, security, race conditions | `adversarial-reviewer` |
| Test quality (tautologies, mocks-only, decorative asserts) | `test-quality-auditor` |
| End-to-end behavior proof (curl, CLI, real probe) | `e2e-verifier` |
| Regressions vs. the last baseline | `regression-hunter` |
| Every claim in the completion report cross-checked | `claim-validator` |
| Stubs, TODOs, completeness | `completeness-auditor` |
| Final verdict aggregation (one FAIL = FAIL) | `final-judge` |

---

## A concrete scenario

> *"Add a `/refund` endpoint. We'll wire up the payment gateway later."*

**Without DoD-Guard:** the orchestrator writes a `return null` stub, adds a test that mocks the gateway and asserts `null`, declares done. The PR ships broken.

**With DoD-Guard:**

1. The orchestrator writes the stub.
2. `PostToolUse` hook fires `detect-stubs.sh`. Returns `count: 2` (TODO marker + suspicious return).
3. Hook emits `{"decision": "block", "reason": "DoD-Guard: 2 issue(s) detected..."}`.
4. The orchestrator cannot continue without either implementing the gateway *or* returning `501 Not Implemented` with a test for that response.
5. Before declaring done, `/dod:confess` forces a 7-section honest report. `claim-validator` cross-checks each claim against the diff.
6. `Stop` hook re-runs verification. PASS only when zero blocking issues remain.

See [docs/EXAMPLES.md](docs/EXAMPLES.md) for four full scenarios.

---

## Customization

Every detector and every hook is tunable per-project via `.dod-guard.json`:

```json
{
  "strictness": "normal",                          // strict | normal | lenient
  "detectors": {
    "stubs":          { "enabled": true, "severity": "block" },
    "test_tautology": { "enabled": true, "severity": "block" }
  },
  "hooks": {
    "post_edit":  { "severity": "block" },
    "pre_commit": { "require_verify_recent": true, "verify_ttl_seconds": 600 },
    "stop_gate":  { "skip_tests": false }
  },
  "audit": {
    "parallel": true,
    "subagents": ["completeness-auditor", "test-quality-auditor", "regression-hunter"]
  },
  "exemptions": {
    "paths": ["**/migrations/**", "vendor/**", "src/generated/**"]
  }
}
```

Highlights:

- Three strictness levels, per-detector severity overrides.
- Custom regex patterns (e.g., a company-specific `@INTERNAL_TODO`).
- Glob-based exemptions (with `DODG_NO_EXEMPTIONS=1` bypass for tests).
- Custom detectors via local `scripts/local/detect-*.py`.
- Per-stack DoD templates auto-selected by `/dod:init` (Node, Go, generic).

Full reference: [docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md).

---

## Project layout

```
.claude-plugin/
  plugin.json                    manifest
  marketplace.json               single-plugin marketplace entry
hooks/
  hooks.json                     event wiring
  handlers/                      5 hook scripts
scripts/
  detect-*.{sh,py}               7 detectors
  run-full-suite.sh              test runner auto-detection
  run-verification-pipeline.sh   aggregator → JSON verdict
  lib/                           shared helpers (exemptions, language detection)
agents/                          7 adversarial subagents
commands/                        8 slash commands
skills/*/SKILL.md                4 behavior-shaping skills
templates/                       .dod-guard.json + DOD.md per stack
docs/                            ARCHITECTURE · CUSTOMIZATION · EXAMPLES · DEVELOPMENT
tests/
  test-*.sh                      4 test suites (94 assertions)
  fixtures/                      negative + clean test projects
```

---

## Verification

The plugin verifies itself. A 94-assertion test suite covers every detector, every hook, and every adversarial agent. Run any of them with one command:

```bash
bash tests/test-detectors.sh        # 28 / 28 — all detectors against fixtures
bash tests/test-hooks.sh            # 18 / 18 — payload simulation for the 5 hooks
bash tests/test-agents-syntax.sh    # 36 / 36 — agent + command frontmatter
bash tests/test-integration.sh      # 12 / 12 — end-to-end init → block → fix → pass
```

`shellcheck -x` is clean on every shell script. `python3 -m py_compile` is clean on every Python script. `claude plugin validate` passes for both `plugin.json` and `marketplace.json`.

The plugin's own source is held to its own rules: `bash scripts/run-verification-pipeline.sh --skip-tests` returns `VERDICT: PASS, 0 issues`.

---

## Contributing

PRs welcome. The short version:

```bash
git clone https://github.com/atoslins/dod-guard
cd dod-guard
bash tests/test-detectors.sh
bash tests/test-hooks.sh
bash tests/test-agents-syntax.sh
bash tests/test-integration.sh
shellcheck -x hooks/handlers/*.sh scripts/*.sh tests/*.sh
```

The contribution guide is in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). Style, testing, and release process are documented there.

Open issues and discussions are tracked at [github.com/atoslins/dod-guard/issues](https://github.com/atoslins/dod-guard/issues).

---

## FAQ

**Can the orchestrator just ignore the hooks?**
No. Hooks are executed by Claude Code itself before and after every tool call. They return JSON the agent must obey (`{"decision": "block"}` halts the turn). The agent literally cannot proceed.

**Doesn't this slow everything down?**
The detectors are bash + Python AST — under 100 ms on small projects, under a second on large ones. The full `/dod:audit` (7 subagents in parallel) takes 2-3 minutes and is meant for end-of-task, not every turn.

**What happens if a hook itself has a bug?**
The `Stop` hook honors `stop_hook_active: true` from the payload — if the hook keeps blocking, Claude Code routes the agent back to the user after one cycle. No infinite loops. Other hooks no-op silently when `.dod-guard.json` is absent.

**Does this replace code review?**
No. It catches the *category* of failure that LLM agents disproportionately produce (premature completion, decorative tests, swallowed errors). Human review still catches design issues, architectural drift, and product-fit problems. Use both.

**Can I disable a specific detector?**
Yes, in `.dod-guard.json`. But prefer narrowing patterns over disabling — the detector is cheap, the value of catching one real bug is high.

---

## Acknowledgments

DoD-Guard borrows ideas from:

- The Claude Code plugin and hook ecosystem.
- The `adversarial-review` pattern of independent skeptic subagents.
- The Test-Driven Development / Definition-of-Done discipline from agile and lean engineering.

The thread that ties them together is a single principle: **evidence before assertion, always.**

---

## License

MIT © Atos Daniel de Assis Lins. See [LICENSE](LICENSE).

<div align="center">
<sub>Built with — and for — Claude Code.</sub>
</div>
