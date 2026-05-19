# DoD-Guard

> Definition of Done as an executable barrier. Stops AI agents (and humans) from declaring tasks "done" while code is still half-baked.

![status](https://img.shields.io/badge/status-alpha-orange)
![claude-code](https://img.shields.io/badge/claude--code-%E2%89%A5%202.1-blue)
![license](https://img.shields.io/badge/license-MIT-green)

## The problem

LLM-driven coding assistants are biased toward declaring "done." Common failure modes:

- Functions left as `pass`, `return None`, `TODO: implement`.
- Tests that only assert `expect(x).toBeDefined()`.
- End-to-end behaviors claimed without a single command being run.
- Regressions in pre-existing tests masked by a "passes 12/14" summary.
- Confident final reports with no evidence chain.

**DoD-Guard** turns the Definition of Done into something the agent cannot talk its way past.

## How it works

Five reinforcing layers:

1. **Deterministic detectors** — bash/Python scripts that grep, parse AST, and flag stubs, tautological tests, and suspicious returns. No LLM in the loop.
2. **Lifecycle hooks** — `PostToolUse` blocks bad edits in real time; `Stop` refuses to let the agent end its turn while DoD is unmet (with proper `stop_hook_active` loop prevention).
3. **Adversarial subagents** — seven read-only validators prompted to assume the orchestrator lied. PASS verdicts require non-empty `commands_run`.
4. **Slash commands** — `/dod:verify`, `/dod:audit`, `/dod:confess`, and friends for manual orchestration.
5. **Skills** — reprogram the orchestrator's behavior whenever `.dod-guard.json` is present in a project.

## Quick install

```bash
# From the Claude Code CLI, inside any session:
/plugin marketplace add https://github.com/atosdaniel/dod-guard
/plugin install dod-guard

# Then, inside any project you want to guard:
/dod:init
```

That creates `.dod-guard.json` and `DOD.md` in the project. From that point on, hooks fire automatically and the orchestrator is held to the Definition of Done.

## Try it without committing

```bash
/dod:stubs        # quick scan for stubs/TODOs in the current diff
/dod:verify       # ~30 second deterministic + LLM-light check
/dod:audit        # full multi-agent audit (~2-3 minutes)
/dod:confess      # force the orchestrator to self-audit honestly
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — how the layers compose
- [Customization](docs/CUSTOMIZATION.md) — `.dod-guard.json`, modes, custom detectors
- [Examples](docs/EXAMPLES.md) — real cases (new feature, bug fix, refactor)
- [Development](docs/DEVELOPMENT.md) — contributing, tests, release process

## License

MIT © Atos Daniel de Assis Lins
