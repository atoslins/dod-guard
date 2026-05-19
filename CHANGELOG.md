# Changelog

All notable changes to **DoD-Guard** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Plugin skeleton, manifest (`.claude-plugin/plugin.json`), license, gitignore, README hero.
- Deterministic detector scripts (`scripts/detect-*.sh`, `scripts/detect-*.py`) covering stubs, TODOs, empty functions, suspicious returns, test tautologies, and `not implemented` markers.
- Lifecycle hooks (`SessionStart`, `PostToolUse`, `Stop`, `SubagentStop`) with loop-safe `stop_hook_active` handling.
- Seven adversarial subagents: completeness-auditor, test-quality-auditor, e2e-verifier, regression-hunter, adversarial-reviewer, claim-validator, final-judge.
- Eight slash commands: `/dod:init`, `/dod:verify`, `/dod:audit`, `/dod:report`, `/dod:stubs`, `/dod:tests`, `/dod:checklist`, `/dod:confess`.
- Four skills modulating orchestrator behavior under DoD-Guard: enforcement, adversarial verification, evidence reporting, stub-detection patterns.
- Templates for `.dod-guard.json` config and `DOD.md`, plus per-stack initializers for Node, Python, Go, Rust.
- Documentation: ARCHITECTURE, CUSTOMIZATION, EXAMPLES, DEVELOPMENT.
- Fixture projects and integration tests under `tests/`.

[Unreleased]: https://github.com/atosdaniel/dod-guard/compare/HEAD...HEAD
