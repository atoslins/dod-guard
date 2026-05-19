#!/usr/bin/env bash
# tests/test-integration.sh
# End-to-end integration test:
#   1. Create a fresh temp project.
#   2. Simulate /dod:init (copy templates, do the substitutions).
#   3. Introduce a stub file.
#   4. Verify post-edit hook would block it.
#   5. Verify run-verification-pipeline.sh returns FAIL.
#   6. Clean the stub. Verify the pipeline now returns PASS.
#
# This does not invoke Claude Code — it directly exercises the deterministic
# parts of the plugin, which is what the slash commands and hooks delegate to.

set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'
PASSED=0
FAILED=0

assert() {
    local name="$1" actual="$2" op="$3" expected="$4"
    local ok=0
    case "$op" in
        ==) [[ "$actual" == "$expected" ]] && ok=1 ;;
        contains) [[ "$actual" == *"$expected"* ]] && ok=1 ;;
        empty) [[ -z "$actual" ]] && ok=1 ;;
    esac
    if [[ "$ok" -eq 1 ]]; then
        PASSED=$((PASSED + 1))
        echo "  ${GREEN}PASS${RESET}  $name"
    else
        FAILED=$((FAILED + 1))
        echo "  ${RED}FAIL${RESET}  $name"
        echo "        actual: '$actual'"
        echo "        op:     $op"
        echo "        wanted: '$expected'"
    fi
}

TMP="$(mktemp -d -t dodg-integration-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 2

echo "Working in: $TMP"
git init -q -b main

echo ""
echo "== Step 1: simulate /dod:init =="
sed -e 's|{{STACK}}|python|g' \
    -e 's|{{STRICTNESS}}|normal|g' \
    -e 's|{{TEST_RUNNER}}|pytest|g' \
    "$ROOT/templates/dod-guard.json.template" > .dod-guard.json
cp "$ROOT/templates/DOD.md.template" DOD.md
mkdir -p .dod-guard/reports

assert "init: .dod-guard.json valid JSON" "$(jq -r .schema_version .dod-guard.json 2>&1)" == "1"
assert "init: DOD.md created" "$(test -f DOD.md && echo yes)" == "yes"
assert "init: .dod-guard dir created" "$(test -d .dod-guard && echo yes)" == "yes"

echo ""
echo "== Step 2: clean project — pipeline PASS =="
cat > calc.py <<'PYEOF'
def add(a: int, b: int) -> int:
    return a + b

def subtract(a: int, b: int) -> int:
    return a - b
PYEOF

result="$(bash "$ROOT/scripts/run-verification-pipeline.sh" --skip-tests --json 2>/dev/null)"
verdict="$(printf '%s' "$result" | jq -r .verdict)"
assert "clean project verdict=PASS" "$verdict" == "PASS"

echo ""
echo "== Step 3: introduce a stub — pipeline should FAIL =="
cat > buggy.py <<'PYEOF'
def create_user(name):
    # TODO: validate input
    return None

def fetch_orders():
    pass
PYEOF

result="$(bash "$ROOT/scripts/run-verification-pipeline.sh" --skip-tests --json 2>/dev/null)"
verdict="$(printf '%s' "$result" | jq -r .verdict)"
total="$(printf '%s' "$result" | jq -r .total_issues)"
assert "with stub verdict=FAIL" "$verdict" == "FAIL"
assert "with stub total_issues > 0" "$total" contains ""
[[ "$total" -ge 3 ]] && PASSED=$((PASSED + 1)) || FAILED=$((FAILED + 1))
echo "  $( [[ "$total" -ge 3 ]] && echo "${GREEN}PASS${RESET}" || echo "${RED}FAIL${RESET}" )  with stub total_issues >= 3  (got $total)"

echo ""
echo "== Step 4: simulate PostToolUse on the stub file =="
payload="$(printf '{"tool_input":{"file_path":"%s"}}' "$(pwd)/buggy.py")"
hook_out="$(printf '%s' "$payload" | bash "$ROOT/hooks/handlers/post-edit.sh")"
assert "post-edit hook blocks stub file" "$hook_out" contains '"decision": "block"'

echo ""
echo "== Step 5: simulate Stop hook — must block because pipeline fails =="
# Fake transcript indicating a Write occurred.
mkdir -p .dod-guard
echo '{"type":"tool_use","name":"Write"}' > .dod-guard/transcript.jsonl
payload="$(printf '{"stop_hook_active": false, "transcript_path": "%s"}' "$(pwd)/.dod-guard/transcript.jsonl")"
hook_out="$(printf '%s' "$payload" | bash "$ROOT/hooks/handlers/stop-gate.sh" 2>/dev/null)"
assert "stop-gate blocks on FAIL verdict" "$hook_out" contains '"decision": "block"'

echo ""
echo "== Step 6: clean the stub — pipeline should PASS again =="
rm -f buggy.py
result="$(bash "$ROOT/scripts/run-verification-pipeline.sh" --skip-tests --json 2>/dev/null)"
verdict="$(printf '%s' "$result" | jq -r .verdict)"
assert "after cleanup verdict=PASS" "$verdict" == "PASS"

echo ""
echo "== Step 7: simulate Stop hook — must release with PASS verdict =="
payload="$(printf '{"stop_hook_active": false, "transcript_path": "%s"}' "$(pwd)/.dod-guard/transcript.jsonl")"
hook_out="$(printf '%s' "$payload" | bash "$ROOT/hooks/handlers/stop-gate.sh" 2>/dev/null)"
assert "stop-gate releases on PASS" "$hook_out" empty ""
assert "stop-gate wrote marker"     "$(test -f .dod-guard/last-verify-passed && echo yes)" == "yes"

echo ""
echo "------------------------------------------------------------"
echo "  ${PASSED} passed, ${FAILED} failed"
echo "------------------------------------------------------------"
[[ "$FAILED" -gt 0 ]] && exit 1
exit 0
