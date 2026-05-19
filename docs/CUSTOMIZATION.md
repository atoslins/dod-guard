# Customization

DoD-Guard's defaults are deliberately strict. Loosen them on a per-project basis through `.dod-guard.json`.

## The configuration file

After `/dod:init`, every consumer project has a `.dod-guard.json` in its root. Every field is optional; omitting a field reverts to defaults.

```json
{
  "strictness": "normal",            // strict | normal | lenient
  "stack": "python",                 // auto-detected; pin to override
  "scope": { "roots": [] },          // monorepo: restrict scan to listed subdirs
  "detectors": { ... },              // per-detector toggles
  "test_runners": { "preferred": "pytest" },
  "verification": {
    "run_tests": true,
    "coverage_drop_tolerance": 1.0
  },
  "hooks": { ... },
  "audit": { "parallel": true, "subagents": [...] },
  "exemptions": { "paths": ["**/migrations/**"] }
}
```

## Strictness levels

| Level | Behavior |
|-------|----------|
| `strict` | warn-level issues also block. Use this for new projects and small libraries. |
| `normal` (default) | high-level issues block; warns are surfaced but do not block. |
| `lenient` | nothing blocks; everything is warned. Use this for prototypes or legacy codebases mid-cleanup. |

Per-detector severity overrides win over the global strictness: setting `detectors.stubs.severity = "warn"` will warn even in `strict` mode.

## Disabling a detector

```json
"detectors": {
  "test_tautology": { "enabled": false }
}
```

Prefer narrowing patterns (below) over fully disabling — the detector is cheap, the value of catching one real bug is high.

## Adding or removing stub patterns

```json
"detectors": {
  "stubs": {
    "enabled": true,
    "severity": "block",
    "patterns": [
      {"type": "todo_marker",   "regex": "TODO[[:space:]:]",                "severity": "high"},
      {"type": "company_marker", "regex": "@INTERNAL_TODO",                  "severity": "high"},
      {"type": "placeholder",   "regex": "REPLACE_ME_LATER",                 "severity": "high"}
    ]
  }
}
```

Patterns use POSIX extended regex (`grep -E`). Validate yours with:

```bash
echo "// @INTERNAL_TODO fix later" | grep -E '@INTERNAL_TODO'
```

## Scoping the audit to subdirectories (monorepos)

In a monorepo, you usually don't want DoD-Guard auditing the entire tree — many sub-projects are out of your team's reach, vendored, or follow a different DoD. Use `scope.roots` to restrict every whole-project scan to a curated subset:

```json
"scope": {
  "roots": ["services/api/", "packages/web/"]
}
```

Semantics:

- Paths are relative to the `.dod-guard.json`. Trailing slashes are optional but recommended for clarity.
- When `scope.roots` is empty or absent, the whole project is scanned (current behavior, no breaking change).
- `--all` mode (default for `/dod:verify`, `/dod:stubs`, `/dod:audit`) iterates **only** the listed roots.
- `--diff` mode (used by hooks and `/dod:checklist`) silently drops files outside any root from the git diff before scanning.
- `exemptions.paths` still applies *inside* each scope root. Think of scope as a positive include list applied first, exemptions as a negative subtract.

`/dod:init` detects monorepos heuristically: if it finds two or more project-marker files (`go.mod`, `package.json`, `pyproject.toml`, `Cargo.toml`) in distinct subdirectories, it prompts you to pick which ones to scope.

Bypass scope at runtime with the env var `DODG_NO_SCOPE=1` — useful when you want a one-off full-project audit without editing the config:

```bash
DODG_NO_SCOPE=1 bash scripts/run-full-suite.sh
```

## Exempting paths

```json
"exemptions": {
  "paths": [
    "**/migrations/**",
    "src/generated/**",
    "vendor/**"
  ]
}
```

Glob syntax is the same as `.gitignore`. Use sparingly: exemptions hide problems. Prefer narrowing patterns instead.

## Hook severity per scenario

```json
"hooks": {
  "post_edit":  { "severity": "warn" },      // do not block edits, only warn
  "pre_commit": {
    "require_stubs_clean":   true,
    "require_tests_pass":    true,
    "require_verify_recent": true,
    "verify_ttl_seconds":    600              // /dod:verify must have passed in the last 10 minutes
  },
  "stop_gate": { "skip_tests": false }        // run the suite at Stop time
}
```

Common combinations:

- **CI mode**: `"skip_tests": false`, `"verify_ttl_seconds": 0` (always require fresh verification).
- **Fast-iteration mode**: `post_edit.severity = "warn"`, `stop_gate.skip_tests = true`. Trust periodic `/dod:verify`.
- **Strict review mode**: `strictness = "strict"`, `verify_ttl_seconds = 60`.

## Subagent selection in /dod:audit

```json
"audit": {
  "parallel": true,
  "subagents": [
    "completeness-auditor",
    "regression-hunter",
    "claim-validator"
  ]
}
```

Remove agents that are not relevant (e.g., `e2e-verifier` if the project is a pure library) to speed up the audit. Always keep `final-judge` (it is added automatically).

## Custom detectors (Python helper)

Drop a script under `scripts/local/` of the consumer project (not the plugin) named `detect-*.py` that emits the same JSON envelope `{count, issues, summary}`. Register it in `.dod-guard.json`:

```json
"detectors": {
  "custom_my_rule": {
    "enabled": true,
    "severity": "block",
    "command": "python3 scripts/local/detect-my-rule.py . --json"
  }
}
```

Then add `custom_my_rule` to the orchestration list in `run-verification-pipeline.sh` (or open a PR).

## Modes

- **Monorepo**: two complementary approaches. (a) Place a `.dod-guard.json` at each package root that needs its own DoD — the plugin uses the nearest config when commands are invoked from inside that package. (b) For a single root-level config that audits only a subset of packages, use `scope.roots` (see *Scoping the audit*). (a) gives per-package customization; (b) gives a single source of truth.
- **CI mode**: set `verification.run_tests = true` and `hooks.pre_commit.verify_ttl_seconds = 0`. Run `/dod:verify` as a step in the pipeline.
- **Offline mode**: set `verification.require_e2e_probe = false`. Subagents will mark e2e as `not_applicable` rather than fail.
