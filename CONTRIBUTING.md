# Contributing to DoD-Guard

Thanks for considering a contribution. The plugin is small and intentionally simple; the bar for changes is "does this catch a real category of completion-claim failure, or fix one that DoD-Guard is currently producing?"

## Quick start

```bash
git clone https://github.com/atoslins/dod-guard
cd dod-guard

# Validate the manifests
jq . .claude-plugin/plugin.json
jq . .claude-plugin/marketplace.json

# Run all test suites
bash tests/test-detectors.sh         # 28 assertions
bash tests/test-hooks.sh             # 18 assertions
bash tests/test-agents-syntax.sh     # 36 assertions
bash tests/test-integration.sh       # 12 assertions

# Lint
shellcheck -x hooks/handlers/*.sh scripts/*.sh tests/*.sh
shellcheck scripts/lib/*.sh
python3 -m py_compile scripts/*.py scripts/lib/*.py

# Self-audit (the plugin must approve its own source)
bash scripts/run-verification-pipeline.sh --skip-tests --text
```

CI runs all of the above on every push and PR. Locally, set things up so all four test suites pass and shellcheck is clean before pushing.

## Required tools

| Tool | Why | Minimum |
|------|-----|---------|
| `bash` | Hook handlers and detectors | 4.0+ |
| `python3` | AST-based detectors | 3.10+ |
| `jq` | JSON parsing | 1.6+ |
| `git` | Diff-based scans | 2.30+ |
| `shellcheck` | Style + safety | 0.9+ |

Optional, for runtime detection of test runners: `pytest`, `node`, `jest`/`vitest`, `go`, `cargo`.

## Where things live

```
.claude-plugin/   plugin.json + marketplace.json
hooks/            hooks.json + 5 handlers
scripts/          detectors + lib + verification-pipeline
agents/           7 adversarial subagents (read-only)
commands/         8 slash commands
skills/           4 SKILL.md
templates/        .dod-guard.json + DOD.md per stack
docs/             full reference (ARCHITECTURE, CUSTOMIZATION, EXAMPLES)
tests/            test-*.sh + fixtures/
```

The full development reference is in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — style, release process, layout, dependencies.

## What good PRs look like

A high-signal PR has:

1. **One concrete bad-code example** in the description that the change now catches.
2. **One concrete good-code example** that the change does *not* false-positive.
3. **All four test suites green** (CI runs them; you can run them locally).
4. **A CHANGELOG entry** under `[Unreleased]`.
5. **Self-audit still passes**: `bash scripts/run-verification-pipeline.sh --skip-tests` returns `VERDICT: PASS`.

The PR template ([.github/pull_request_template.md](.github/pull_request_template.md)) walks through this.

## What's out of scope

- Cosmetic refactors with no behavioral motivation.
- Adding linting rules already covered by the project's own linters (eslint, ruff, golangci-lint). DoD-Guard fights completion-claim failures, not style.
- Suggestions to make the agent "less strict by default." Strictness is per-project via `.dod-guard.json`.
- Bypass mechanisms (`--no-verify`, `DODG_SKIP_ALL`, etc.). The whole point is that the wall doesn't open.

## Code of conduct

Be respectful. Assume good intent. Critique the code, not the contributor.

## Reporting bugs and asking questions

- **Bugs** → [Issues](https://github.com/atoslins/dod-guard/issues) (use the bug template).
- **Feature ideas** → [Issues](https://github.com/atoslins/dod-guard/issues) (use the feature template).
- **Open-ended questions / usage help / design discussion** → [Discussions](https://github.com/atoslins/dod-guard/discussions).

## License

By contributing, you agree your contribution will be licensed under the [MIT License](LICENSE), the same as the project.
