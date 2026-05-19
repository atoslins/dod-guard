#!/usr/bin/env bash
# hooks/handlers/pre-commit.sh
# PostToolUse hook for Bash. Fires for every shell command; we only act when
# the command is a `git commit`. Blocks the commit if the DoD is not met.
#
# Input JSON (stdin): { "tool_input": { "command": "<shell text>" }, ... }
# Output JSON (stdout): {"decision":"block","reason":...} when blocking.

set -uo pipefail

PLUGIN_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/../.. && pwd)"
SCRIPT_DIR="$PLUGIN_ROOT/scripts"

payload="$(cat || true)"

if [[ ! -f ".dod-guard.json" ]]; then
    exit 0
fi

# Extract the shell command. Skip if jq absent and we cannot parse safely.
cmd=""
if command -v jq >/dev/null 2>&1; then
    cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
fi
if [[ -z "$cmd" ]]; then
    cmd="$(printf '%s' "$payload" | grep -oE '"command"\s*:\s*"[^"]+"' | head -n 1 | sed -E 's/.*"command"\s*:\s*"([^"]+)".*/\1/' || true)"
fi

# Only act on `git commit` invocations. Reject `--no-verify` outright.
shopt -s nocasematch
case "$cmd" in
    *"git commit"*) : ;;
    *) exit 0 ;;
esac

if [[ "$cmd" == *"--no-verify"* ]]; then
    python3 - <<'PYEOF'
import json
print(json.dumps({"decision": "block",
                  "reason": "DoD-Guard: --no-verify is forbidden by policy. If a hook is failing, fix the root cause; do not bypass."}))
PYEOF
    exit 0
fi
shopt -u nocasematch

# Per-config switches.
require_stubs_clean=true
require_tests_pass=true
require_verify_recent=true
verify_ttl_seconds=600

if command -v jq >/dev/null 2>&1; then
    v="$(jq -r '.hooks.pre_commit.require_stubs_clean   // empty' .dod-guard.json 2>/dev/null)"; [[ -n "$v" ]] && require_stubs_clean="$v"
    v="$(jq -r '.hooks.pre_commit.require_tests_pass    // empty' .dod-guard.json 2>/dev/null)"; [[ -n "$v" ]] && require_tests_pass="$v"
    v="$(jq -r '.hooks.pre_commit.require_verify_recent // empty' .dod-guard.json 2>/dev/null)"; [[ -n "$v" ]] && require_verify_recent="$v"
    v="$(jq -r '.hooks.pre_commit.verify_ttl_seconds    // empty' .dod-guard.json 2>/dev/null)"; [[ -n "$v" ]] && verify_ttl_seconds="$v"
fi

reasons=()

# 1. Stubs in staged diff.
if [[ "$require_stubs_clean" == "true" ]]; then
    stubs_json="$(bash "$SCRIPT_DIR/detect-stubs.sh" --diff --json 2>/dev/null || true)"
    stubs_count=0
    if command -v jq >/dev/null 2>&1; then
        stubs_count="$(printf '%s' "$stubs_json" | jq -r '.count // 0' 2>/dev/null || echo 0)"
    fi
    if [[ "${stubs_count:-0}" -gt 0 ]]; then
        reasons+=("$stubs_count stub-style issue(s) in staged changes")
    fi
fi

# 2. Recent /dod:verify success — keeps the test run off the critical path.
if [[ "$require_verify_recent" == "true" ]]; then
    marker=".dod-guard/last-verify-passed"
    fresh=0
    if [[ -f "$marker" ]]; then
        age=$(( $(date +%s) - $(stat -c %Y "$marker" 2>/dev/null || stat -f %m "$marker" 2>/dev/null || echo 0) ))
        [[ "$age" -le "$verify_ttl_seconds" ]] && fresh=1
    fi
    if [[ "$fresh" -eq 0 ]]; then
        reasons+=("/dod:verify has not passed in the last $verify_ttl_seconds seconds")
    fi
fi

# 3. Optional full test run — only when verify marker is stale.
if [[ "$require_tests_pass" == "true" && ${#reasons[@]} -gt 0 ]]; then
    suite_json="$(bash "$SCRIPT_DIR/run-full-suite.sh" --quiet 2>/dev/null || true)"
    rc=0
    if command -v jq >/dev/null 2>&1; then
        rc="$(printf '%s' "$suite_json" | jq -r '.exit_code // 0' 2>/dev/null || echo 0)"
    fi
    if [[ "${rc:-0}" -ne 0 ]]; then
        reasons+=("test suite exited non-zero")
    fi
fi

if [[ ${#reasons[@]} -eq 0 ]]; then
    exit 0
fi

reason="DoD-Guard: commit blocked. Reasons:"$'\n'
for r in "${reasons[@]}"; do
    reason+="  - $r"$'\n'
done
reason+="Run /dod:verify, fix the issues, then retry."

python3 - "$reason" <<'PYEOF'
import json, sys
print(json.dumps({"decision": "block", "reason": sys.argv[1]}))
PYEOF
exit 0
