#!/usr/bin/env bash
# scripts/run-verification-pipeline.sh
# Orchestrate every deterministic detector and the test runner, then emit a
# single aggregated verdict. Hooks and slash commands consume this output.
#
# Usage: run-verification-pipeline.sh [--skip-tests] [--json|--text]

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

SKIP_TESTS=0
FORMAT="json"
for arg in "$@"; do
    case "$arg" in
        --skip-tests) SKIP_TESTS=1 ;;
        --json) FORMAT="json" ;;
        --text) FORMAT="text" ;;
        --help|-h)
            sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
    esac
done

# Load config (toggles per detector). Defaults: everything on, severity "block"
# means a non-zero count fails the pipeline.
CFG=".dod-guard.json"
cfg_get() {
    local query="$1" default="$2"
    if [[ -f "$CFG" ]] && command -v jq >/dev/null 2>&1; then
        local v
        v="$(jq -r "$query // empty" "$CFG" 2>/dev/null || true)"
        if [[ -n "$v" && "$v" != "null" ]]; then
            printf '%s' "$v"
            return
        fi
    fi
    printf '%s' "$default"
}

stubs_enabled="$(cfg_get '.detectors.stubs.enabled' true)"
# Reserved for future severity-aware verdicts; deliberately read but unused.
_stubs_severity="$(cfg_get '.detectors.stubs.severity' block)"
empty_fn_enabled="$(cfg_get '.detectors.empty_functions.enabled' true)"
susp_ret_enabled="$(cfg_get '.detectors.suspicious_returns.enabled' true)"
tautology_enabled="$(cfg_get '.detectors.test_tautology.enabled' true)"
ni_enabled="$(cfg_get '.detectors.not_implemented.enabled' true)"
run_tests="$(cfg_get '.verification.run_tests' true)"

# Run each detector; aggregate counts and issues.
declare -a STEP_RESULTS=()
RUN_DETECTOR() {
    local name="$1" cmd="$2"
    local out rc
    out="$(eval "$cmd" 2>/dev/null || true)"
    rc=$?
    # Default count = 0 when the command failed to produce JSON.
    local count
    if command -v jq >/dev/null 2>&1; then
        count="$(printf '%s' "$out" | jq -r '.count // 0' 2>/dev/null || echo 0)"
    else
        count="$(printf '%s' "$out" | grep -oE '"count":[0-9]+' | head -n 1 | cut -d: -f2)"
        count=${count:-0}
    fi
    STEP_RESULTS+=("$(printf '{"step":"%s","count":%s,"rc":%s,"output":%s}' \
        "$name" "$count" "$rc" "$(printf '%s' "$out" | python3 -c 'import json,sys;sys.stdout.write(json.dumps(sys.stdin.read()))')")")
}

if [[ "$stubs_enabled" == "true" ]]; then
    RUN_DETECTOR "stubs" "bash '$SCRIPT_DIR/detect-stubs.sh' --all --json"
fi
if [[ "$empty_fn_enabled" == "true" ]]; then
    RUN_DETECTOR "empty_functions" "python3 '$SCRIPT_DIR/detect-empty-functions.py' . --json"
fi
if [[ "$susp_ret_enabled" == "true" ]]; then
    RUN_DETECTOR "suspicious_returns" "python3 '$SCRIPT_DIR/detect-suspicious-returns.py' . --json"
fi
if [[ "$tautology_enabled" == "true" ]]; then
    RUN_DETECTOR "test_tautology" "python3 '$SCRIPT_DIR/detect-test-tautology.py' . --json"
fi
if [[ "$ni_enabled" == "true" ]]; then
    RUN_DETECTOR "not_implemented" "bash '$SCRIPT_DIR/check-not-implemented.sh' . --json"
fi

# Test runner
TESTS_JSON='{"runner":"skipped","passed":0,"failed":0,"skipped":0,"duration_ms":0,"exit_code":0,"raw_output":""}'
TESTS_RC=0
if [[ "$run_tests" == "true" && "$SKIP_TESTS" -eq 0 ]]; then
    TESTS_JSON="$(bash "$SCRIPT_DIR/run-full-suite.sh" --quiet 2>/dev/null || true)"
    if command -v jq >/dev/null 2>&1; then
        TESTS_RC="$(printf '%s' "$TESTS_JSON" | jq -r '.exit_code // 0')"
    fi
fi

# Verdict: any detector with non-zero count and severity=block => FAIL.
total_issues=0
fail_reasons=()
for step_json in "${STEP_RESULTS[@]}"; do
    if command -v jq >/dev/null 2>&1; then
        step_name="$(printf '%s' "$step_json" | jq -r '.step')"
        step_count="$(printf '%s' "$step_json" | jq -r '.count')"
    else
        step_name="$(printf '%s' "$step_json" | grep -oE '"step":"[^"]+"' | head -n 1 | cut -d: -f2 | tr -d '"')"
        step_count="$(printf '%s' "$step_json" | grep -oE '"count":[0-9]+' | head -n 1 | cut -d: -f2)"
    fi
    total_issues=$((total_issues + step_count))
    if [[ "$step_count" -gt 0 ]]; then
        fail_reasons+=("$step_name=$step_count")
    fi
done

if [[ "$TESTS_RC" -ne 0 && "$SKIP_TESTS" -eq 0 ]]; then
    fail_reasons+=("tests_failed")
fi

verdict="PASS"
if [[ ${#fail_reasons[@]} -gt 0 ]]; then
    verdict="FAIL"
fi

if [[ "$FORMAT" == "text" ]]; then
    echo "=== DoD-Guard Verification Pipeline ==="
    for step_json in "${STEP_RESULTS[@]}"; do
        if command -v jq >/dev/null 2>&1; then
            printf '%s' "$step_json" | jq -r '"  \(.step | ascii_upcase):  \(.count) issue(s)"'
        else
            echo "  $step_json"
        fi
    done
    if [[ "$run_tests" == "true" && "$SKIP_TESTS" -eq 0 ]]; then
        if command -v jq >/dev/null 2>&1; then
            printf '%s' "$TESTS_JSON" | jq -r '"  TESTS:  runner=\(.runner) passed=\(.passed) failed=\(.failed) skipped=\(.skipped)"'
        fi
    fi
    echo "  TOTAL ISSUES: $total_issues"
    echo "  VERDICT: $verdict"
    [[ ${#fail_reasons[@]} -gt 0 ]] && echo "  REASONS: ${fail_reasons[*]}"
else
    # Compose final JSON. Steps array + tests + verdict.
    steps_csv="$(IFS=,; echo "${STEP_RESULTS[*]}")"
    reasons_arr="[]"
    if [[ ${#fail_reasons[@]} -gt 0 ]]; then
        # Build the JSON array manually — bash IFS join can't insert a multi-char separator.
        joined=""
        for r in "${fail_reasons[@]}"; do
            if [[ -z "$joined" ]]; then
                joined="\"$r\""
            else
                joined="$joined,\"$r\""
            fi
        done
        reasons_arr="[$joined]"
    fi
    printf '{"verdict":"%s","total_issues":%s,"reasons":%s,"steps":[%s],"tests":%s}\n' \
        "$verdict" "$total_issues" "$reasons_arr" "$steps_csv" "$TESTS_JSON"
fi

if [[ "$verdict" == "FAIL" ]]; then
    exit 1
fi
exit 0
