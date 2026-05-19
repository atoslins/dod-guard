#!/usr/bin/env bash
# tests/test-hooks.sh
# Simulate Claude Code hook payloads and assert each handler behaves correctly.

set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
PASSED=0
FAILED=0
GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'

assert() {
    local name="$1" actual="$2" op="$3" expected="$4"
    local ok=0
    case "$op" in
        ==) [[ "$actual" == "$expected" ]] && ok=1 ;;
        contains) [[ "$actual" == *"$expected"* ]] && ok=1 ;;
        empty) [[ -z "$actual" ]] && ok=1 ;;
        not_contains) [[ "$actual" != *"$expected"* ]] && ok=1 ;;
    esac
    if [[ "$ok" -eq 1 ]]; then
        PASSED=$((PASSED + 1))
        echo "  ${GREEN}PASS${RESET}  $name"
    else
        FAILED=$((FAILED + 1))
        echo "  ${RED}FAIL${RESET}  $name"
        echo "        actual:   '$actual'"
        echo "        op:       $op"
        echo "        expected: '$expected'"
    fi
}

# Create an isolated test workspace where we can pretend to be a guarded project.
TMP="$(mktemp -d -t dodg-test-hooks-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 2

echo "Working in: $TMP"

# ----- Case A: no .dod-guard.json present (every hook must no-op).
echo ""
echo "== A: no DoD-Guard config — handlers should be silent no-ops =="
out_a="$(echo '{}' | bash "$ROOT/hooks/handlers/session-start.sh" 2>&1)"
assert "session-start no-op (no config)"   "$out_a" empty ""
out_a="$(echo '{"tool_input":{"file_path":"x.py"}}' | bash "$ROOT/hooks/handlers/post-edit.sh" 2>&1)"
assert "post-edit no-op (no config)"       "$out_a" empty ""
out_a="$(echo '{"tool_input":{"command":"git commit -m foo"}}' | bash "$ROOT/hooks/handlers/pre-commit.sh" 2>&1)"
assert "pre-commit no-op (no config)"      "$out_a" empty ""
out_a="$(echo '{}' | bash "$ROOT/hooks/handlers/stop-gate.sh" 2>&1)"
assert "stop-gate no-op (no config)"       "$out_a" empty ""

# ----- Add the config and minimal project content for the remaining cases.
git init -q
echo '{"detectors":{"stubs":{"enabled":true,"severity":"block"}},"hooks":{"post_edit":{"severity":"block"},"stop_gate":{"skip_tests":true},"pre_commit":{"require_verify_recent":true,"require_stubs_clean":true,"require_tests_pass":false,"verify_ttl_seconds":600}},"verification":{"run_tests":false}}' > .dod-guard.json
echo "# DoD" > DOD.md

echo ""
echo "== B: SessionStart with config — must emit additionalContext =="
out_b="$(echo '{}' | bash "$ROOT/hooks/handlers/session-start.sh")"
assert "session-start emits envelope" "$out_b" contains '"additionalContext"'
assert "session-start mentions DoD-Guard" "$out_b" contains "DoD-Guard"

echo ""
echo "== C: PostToolUse Edit — file with stubs must block =="
cat > stub.py <<'PYEOF'
def create_user(name):
    # TODO: validate name
    return None
PYEOF
# Use absolute path in payload to match real Claude Code behavior.
abs_path="$(pwd)/stub.py"
payload="$(printf '{"tool_input":{"file_path":"%s"}}' "$abs_path")"
out_c="$(printf '%s' "$payload" | bash "$ROOT/hooks/handlers/post-edit.sh")"
assert "post-edit blocks on stub file" "$out_c" contains '"decision": "block"'
assert "post-edit reason mentions TODO" "$out_c" contains "TODO"

echo ""
echo "== D: PostToolUse Edit on a clean file — must not block =="
cat > clean.py <<'PYEOF'
def add(a, b):
    return a + b
PYEOF
abs_path="$(pwd)/clean.py"
payload="$(printf '{"tool_input":{"file_path":"%s"}}' "$abs_path")"
out_d="$(printf '%s' "$payload" | bash "$ROOT/hooks/handlers/post-edit.sh")"
assert "post-edit silent on clean file" "$out_d" not_contains "block"

echo ""
echo "== E: pre-commit on plain bash (not a git commit) — must no-op =="
payload='{"tool_input":{"command":"ls -la"}}'
out_e="$(printf '%s' "$payload" | bash "$ROOT/hooks/handlers/pre-commit.sh")"
assert "pre-commit no-op on non-commit" "$out_e" empty ""

echo ""
echo "== F: pre-commit on git commit --no-verify — must block =="
payload='{"tool_input":{"command":"git commit --no-verify -m foo"}}'
out_f="$(printf '%s' "$payload" | bash "$ROOT/hooks/handlers/pre-commit.sh")"
assert "pre-commit blocks --no-verify" "$out_f" contains '"decision": "block"'
assert "pre-commit reason cites --no-verify" "$out_f" contains "no-verify"

echo ""
echo "== G: pre-commit blocks when /dod:verify never ran =="
payload='{"tool_input":{"command":"git commit -m foo"}}'
out_g="$(printf '%s' "$payload" | bash "$ROOT/hooks/handlers/pre-commit.sh")"
assert "pre-commit blocks (no verify marker)" "$out_g" contains '"decision": "block"'

echo ""
echo "== H: stop-gate loop prevention — stop_hook_active=true must exit clean =="
payload='{"stop_hook_active": true}'
out_h="$(printf '%s' "$payload" | bash "$ROOT/hooks/handlers/stop-gate.sh")"
assert "stop-gate releases when stop_hook_active" "$out_h" empty ""

echo ""
echo "== I: stop-gate without active flag — blocks because pipeline FAILs =="
# Make sure stub.py is still there so the pipeline finds something.
payload='{"stop_hook_active": false}'
out_i="$(printf '%s' "$payload" | bash "$ROOT/hooks/handlers/stop-gate.sh" 2>/dev/null)"
assert "stop-gate blocks on FAIL verdict" "$out_i" contains '"decision": "block"'

echo ""
echo "== J: stop-gate PASS path — clean project, no mutations recorded =="
# Remove stub.py so the pipeline passes.
rm -f stub.py
# Create a fake transcript with no Write/Edit events; stop-gate should bail.
mkdir -p .dod-guard
echo '{"event":"user_message"}' > .dod-guard/fake_transcript.jsonl
payload="$(printf '{"stop_hook_active": false, "transcript_path": "%s"}' "$(pwd)/.dod-guard/fake_transcript.jsonl")"
out_j="$(printf '%s' "$payload" | bash "$ROOT/hooks/handlers/stop-gate.sh")"
assert "stop-gate no-op when no mutations" "$out_j" empty ""

echo ""
echo "== K: subagent-stop records to .dod-guard/reports =="
payload='{"session_id":"s1","agent_name":"completeness-auditor","output":"PASS"}'
printf '%s' "$payload" | bash "$ROOT/hooks/handlers/subagent-stop.sh"
report=".dod-guard/reports/s1/completeness-auditor.json"
if [[ -f "$report" ]]; then
    assert "subagent-stop writes report" "$(cat "$report")" contains "completeness-auditor"
else
    FAILED=$((FAILED + 1))
    echo "  ${RED}FAIL${RESET}  subagent-stop writes report (file not found)"
fi

echo ""
echo "== L: hooks.json validates as JSON =="
if jq empty "$ROOT/hooks/hooks.json" 2>/dev/null; then
    PASSED=$((PASSED + 1))
    echo "  ${GREEN}PASS${RESET}  hooks.json is valid JSON"
else
    FAILED=$((FAILED + 1))
    echo "  ${RED}FAIL${RESET}  hooks.json is not valid JSON"
fi

echo ""
echo "------------------------------------------------------------"
echo "  ${PASSED} passed, ${FAILED} failed"
echo "------------------------------------------------------------"
[[ "$FAILED" -gt 0 ]] && exit 1
exit 0
