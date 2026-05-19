# Changelog

All notable changes to **DoD-Guard** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- (nothing yet)

## [0.2.0] - 2026-05-19

Monorepo-aware audits.

### Added
- `scope.roots` field in `.dod-guard.json` — monorepo scoping. Detectors restrict whole-project scans (`--all`) and git-diff filtering (`--diff`) to the listed subdirectories, leaving sibling sub-projects untouched. Bypass at runtime with `DODG_NO_SCOPE=1`. Default value is `[]`, preserving current behavior.
- `/dod:init` now detects monorepos: when two or more project-marker files (`go.mod`, `package.json`, `pyproject.toml`, `Cargo.toml`) are found in distinct subdirectories, it prompts to pick which roots to scope.
- `path_in_scope` helper in `scripts/lib/languages.sh` and `apply_scope` in `scripts/lib/exemptions.py` for shell and Python detectors respectively.
- Fixture `tests/fixtures/project-monorepo/` and 7 new assertions in `tests/test-detectors.sh` covering scope filtering for both `detect-stubs.sh --all` and `detect-empty-functions.py`.

### Docs
- `docs/CUSTOMIZATION.md` gains a "Scoping the audit to subdirectories" section and updates the "Monorepo" mode entry to compare the two strategies (nearest-config vs. root-level `scope.roots`).

## [0.1.0] - 2026-05-19

First public release.

### Added
- Plugin skeleton, manifest (`.claude-plugin/plugin.json`), single-plugin marketplace (`marketplace.json`), MIT license, gitignore.
- Eleven deterministic detector scripts under `scripts/`: stub markers, TODO/FIXME, empty functions (AST for Python, regex for JS/TS/Go/Rust/Ruby), suspicious returns (action-named fns returning empty literals), test tautologies, `not implemented` markers, full-suite runner detection (pytest/jest/vitest/go/cargo), coverage delta, verification pipeline aggregator.
- Five lifecycle hooks (`SessionStart`, `PostToolUse Write|Edit|MultiEdit`, `PostToolUse Bash`, `Stop`, `SubagentStop`) with loop-safe `stop_hook_active` handling; `--no-verify` rejected outright.
- Seven adversarial subagents: completeness-auditor, test-quality-auditor, e2e-verifier, regression-hunter, adversarial-reviewer, claim-validator, final-judge. All read-only, evidence-gated (PASS requires non-empty `commands_run`).
- Eight slash commands: `/dod:init`, `/dod:verify`, `/dod:audit`, `/dod:report`, `/dod:stubs`, `/dod:tests`, `/dod:checklist`, `/dod:confess`.
- Four skills modulating orchestrator behavior under DoD-Guard: enforcement, adversarial verification, evidence reporting, stub-detection patterns.
- Per-stack DoD templates (`templates/DOD-node.md.template`, `templates/DOD-go.md.template`, generic). `/dod:init` auto-selects by detected stack.
- Project-level `.dod-guard.json` template with strictness levels, per-detector severity, exemption globs, audit subagent selection, custom regex patterns.
- Documentation: ARCHITECTURE, CUSTOMIZATION, EXAMPLES, DEVELOPMENT, public-facing README.
- Test fixtures (`project-clean`, `project-with-stubs`, `project-broken-tests`, `project-js-stubs`, `project-go-stubs`) and four test suites totaling 94 assertions (`test-detectors.sh`, `test-hooks.sh`, `test-agents-syntax.sh`, `test-integration.sh`).
- JavaScript/TypeScript test-tautology coverage: `expect(mock).toHaveBeenCalled()` without args, `expect.assertions(0)`, trivial `toMatchSnapshot`, Node `assert.ok(true)`, chai `.to.be.ok` / `.to.exist`.
- Go-specific detectors: new `scan_go()` in `detect-test-tautology.py` (testify tautologies, `t.Skip` in diff, tests without assertions, `t.Log("TODO...")`), uninitialized-constructor detection (`NewX() *X { return &X{} }`), error-swallow (`_ = err`, `_, _ = ...`), `// nolint:` markers added in the diff.
- GitHub Actions CI workflow running all four test suites + shellcheck + self-audit on every push and PR.
- Issue templates (bug, feature), PR template with DoD-Guard self-checklist, `CONTRIBUTING.md`.

[Unreleased]: https://github.com/atoslins/dod-guard/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/atoslins/dod-guard/releases/tag/v0.2.0
[0.1.0]: https://github.com/atoslins/dod-guard/releases/tag/v0.1.0
