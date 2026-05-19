# Development

How to contribute to DoD-Guard.

## Local setup

```bash
git clone https://github.com/atosdaniel/dod-guard
cd dod-guard

# Validate the manifest
jq . .claude-plugin/plugin.json

# Run the deterministic detector tests
bash tests/test-detectors.sh

# Run the hook simulation tests
bash tests/test-hooks.sh

# Run the agent/command frontmatter validator
bash tests/test-agents-syntax.sh
```

The plugin has no runtime install step. Loading it into Claude Code is a separate concern.

## Required tools

| Tool | Why | Minimum |
|------|-----|---------|
| `bash` | Hook handlers and detectors | 4.0+ |
| `python3` | AST-based detectors | 3.10+ |
| `jq` | JSON parsing in hooks | 1.6+ |
| `git` | Diff-based scans | 2.30+ |
| `shellcheck` | CI linting | 0.9+ |

Optional, for the test fixtures and the `run-full-suite.sh` runner detection:

- `pytest` 7+
- `node` 18+ with `jest`/`vitest` available via npx
- `go` 1.21+
- `cargo` 1.70+

## Layout

```
dod-guard/
  .claude-plugin/plugin.json
  hooks/
    hooks.json
    handlers/*.sh
  scripts/
    *.sh  *.py
    lib/*.sh
  agents/*.md
  commands/*.md
  skills/*/SKILL.md
  templates/*.template
  docs/*.md
  tests/
    fixtures/{clean,with-stubs,broken-tests}/
    test-*.sh
```

## Testing

All tests are shell scripts that exit non-zero on failure. They are meant to be runnable both locally and in CI without any extra setup.

```bash
# Run all tests
bash tests/test-detectors.sh
bash tests/test-hooks.sh
bash tests/test-agents-syntax.sh
```

Add new test cases by appending an `assert` line. The `assert` function is in each script.

## Style guidelines

### Shell

- `#!/usr/bin/env bash` shebang.
- `set -uo pipefail` at the top.
- All globals UPPER_CASE; all locals `local`-declared.
- Quote every variable expansion: `"$foo"`, not `$foo`.
- Pass `shellcheck -x` cleanly. If you need to silence a warning, add a comment `# shellcheck disable=SCxxxx` with a one-line reason.

### Python

- Stdlib only by default. If you need a dependency, document it in `requirements-dev.txt` and add a feature flag.
- Type hints on public functions.
- `argparse` for CLIs, not `sys.argv` parsing by hand.
- Output JSON via `json.dump`, never by string-formatting.

### Markdown (agents, commands, skills)

- Frontmatter is YAML between `---` markers.
- Agents need `name` and `description`; commands need only `description`.
- Skills need `name` and a description that explicitly says when to use.
- Body uses `##` for top-level sections.

## Pull request checklist

- [ ] `tests/test-detectors.sh` passes
- [ ] `tests/test-hooks.sh` passes
- [ ] `tests/test-agents-syntax.sh` passes
- [ ] `shellcheck -x` clean on every shell script you touched
- [ ] Documentation updated where the public surface changed
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]`

## Release process

1. Bump `version` in `.claude-plugin/plugin.json` (semver).
2. Move `[Unreleased]` entries in `CHANGELOG.md` to a new dated section.
3. Tag: `git tag -a v0.X.0 -m "release v0.X.0"`.
4. Push tag: `git push origin v0.X.0`.
5. Update the marketplace listing (separate workflow).
