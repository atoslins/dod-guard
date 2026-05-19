# DoD-Guard

> Definition of Done as an executable barrier. Stops AI agents (and humans) from declaring tasks "done" while code is still half-baked.

![status](https://img.shields.io/badge/status-alpha-orange)
![claude-code](https://img.shields.io/badge/claude--code-%E2%89%A5%202.1-blue)
![license](https://img.shields.io/badge/license-MIT-green)
![python](https://img.shields.io/badge/python-%E2%89%A5%203.10-blue)
![bash](https://img.shields.io/badge/bash-%E2%89%A5%204.0-blue)

## Table of contents

- [The problem](#the-problem)
- [How it works](#how-it-works)
- [Install](#install)
- [First-run](#first-run)
- [The commands](#the-commands)
- [What gets caught](#what-gets-caught)
- [Customization](#customization)
- [Architecture](#architecture)
- [Contributing](#contributing)
- [License](#license)

## The problem

LLM-driven coding assistants are biased toward declaring "done." Common failure modes:

- Functions left as `pass`, `return None`, `TODO: implement`.
- Tests that only assert `expect(x).toBeDefined()` — they validate that the function exists, not that it works.
- End-to-end behaviors claimed without a single command being run.
- Regressions in pre-existing tests masked by a "passes 12/14" summary.
- Confident final reports with no evidence chain.

DoD-Guard turns the Definition of Done into something the agent cannot talk its way past. Hooks block at the source of every shortcut; subagents audit the orchestrator from the outside; the `Stop` hook refuses to release the agent while the DoD is unmet.

## How it works

Five reinforcing layers:

1. **Deterministic detectors** — bash / Python scripts that grep, parse AST, and flag stubs, tautological tests, and suspicious returns. Zero LLM in the loop.
2. **Lifecycle hooks** — `PostToolUse` blocks bad edits in real time; `Stop` refuses to let the agent end its turn while DoD is unmet (with proper `stop_hook_active` loop prevention).
3. **Adversarial subagents** — seven read-only validators prompted to assume the orchestrator lied. PASS verdicts require non-empty `commands_run`.
4. **Slash commands** — `/dod:verify`, `/dod:audit`, `/dod:confess`, and friends for manual orchestration.
5. **Skills** — reprogram the orchestrator's behavior whenever `.dod-guard.json` is present in a project.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the layer diagram and the flow on "Claude declares done."

## Install

From inside any Claude Code session:

```bash
/plugin marketplace add https://github.com/atosdaniel/dod-guard
/plugin install dod-guard
```

To develop locally:

```bash
git clone https://github.com/atosdaniel/dod-guard
/plugin marketplace add ./dod-guard
/plugin install dod-guard@local
```

## First-run

Inside any project you want to guard:

```bash
/dod:init                # creates .dod-guard.json + DOD.md + .dod-guard/
/dod:checklist           # shows the Definition of Done
/dod:verify              # 30-second deterministic check
```

That's it. From that point on, hooks fire automatically on every edit, every commit attempt, and every turn-end.

## The commands

| Command | Purpose | Time |
|---------|---------|------|
| `/dod:init` | Bootstrap config and DoD checklist for the project | < 5s |
| `/dod:verify` | Fast 5-phase deterministic check, refreshes the marker | ~30s |
| `/dod:audit` | Full multi-agent audit (7 subagents) | 2-3 min |
| `/dod:report` | Read existing reports, format markdown — no LLM | < 1s |
| `/dod:stubs` | Fastest scan: stubs and TODOs only | ~2s |
| `/dod:tests` | Audit only test quality (post-TDD) | ~30s |
| `/dod:checklist` | Show DoD with this session's auto-verified items | < 5s |
| `/dod:confess` | Force a 7-section paranoid self-audit | ~10s |

## What gets caught

| Pattern | Where detected |
|---------|---------------|
| `pass` / `...` / `return None` / `{}` as function body | `detect-empty-functions.py` (AST) |
| `TODO`, `FIXME`, `XXX`, `HACK` markers | `detect-stubs.sh` and `detect-todos.sh --diff` |
| `NotImplementedError`, `todo!()`, `unimplemented!()`, `panic("not implemented")` | `check-not-implemented.sh` |
| Action-named functions that return only `null` / `{}` / `[]` | `detect-suspicious-returns.py` |
| `expect(x).toBeDefined()` / `.not.toBeNull()` / `expect(x).toEqual(x)` | `detect-test-tautology.py` |
| `test.skip` / `xit` / `@pytest.mark.skip` added in this diff | `detect-test-tautology.py` |
| Regressions vs. the last baseline | `regression-hunter` subagent |
| Claims with no supporting code | `claim-validator` subagent |
| Bugs, edge cases, security issues | `adversarial-reviewer` subagent |
| Missing e2e probe | `e2e-verifier` subagent |

## Customization

Every detector and every hook can be tuned per-project via `.dod-guard.json`. See [docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md) for the full reference. Highlights:

- Three strictness levels: `strict`, `normal`, `lenient`.
- Per-detector enable / disable / severity.
- Custom regex patterns for stub markers (e.g., a company-specific `@INTERNAL_TODO`).
- Exempt paths (`migrations/`, `vendor/`, generated code).
- Custom detectors via local `scripts/local/detect-*.py`.

## Architecture

Five layers, ordered by cost-to-execute (cheapest first):

```
Detectors  (bash + python, milliseconds)
  ↓
Hooks      (SessionStart, PostToolUse, Stop, SubagentStop)
  ↓
Subagents  (read-only, adversarial, JSON envelope)
  ↓
Slash commands  (manual triggers)
  ↓
Skills     (reframe orchestrator behavior)
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the diagram and flow.

## Examples

[docs/EXAMPLES.md](docs/EXAMPLES.md) walks through four real scenarios:

1. New feature on a clean project (PASS).
2. Bug fix that introduces a regression (FAIL → fix → PASS).
3. Tempted to ship a stub (`return null` from `refund(...)`); blocked at the source.
4. Refactor with no behavior change (e2e marked `unverifiable`, accepted by `final-judge`).

## Contributing

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). The short version:

```bash
bash tests/test-detectors.sh
bash tests/test-hooks.sh
bash tests/test-agents-syntax.sh
shellcheck -x hooks/handlers/*.sh scripts/*.sh
```

PRs are welcome. Read the development guide for style and the release process.

## License

MIT © Atos Daniel de Assis Lins. See [LICENSE](LICENSE).
