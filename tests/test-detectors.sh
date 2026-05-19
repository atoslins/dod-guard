#!/usr/bin/env bash
# tests/test-detectors.sh
# Run every Phase-2 detector against the fixtures and assert expected outputs.
#
# Exit codes: 0 = all tests passed; 1 = at least one failed.

set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
cd "$ROOT" || exit 2

# Bypass project-level exemptions while running detector unit tests; the
# fixtures live under tests/fixtures/ which the plugin's own .dod-guard.json
# exempts from real audits.
export DODG_NO_EXEMPTIONS=1

GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'
PASSED=0
FAILED=0

assert() {
    local name="$1" actual="$2" op="$3" expected="$4"
    local ok=0
    case "$op" in
        ==)  [[ "$actual" == "$expected" ]] && ok=1 ;;
        '>=') [[ "$actual" -ge "$expected" ]] && ok=1 ;;
        '>')  [[ "$actual" -gt "$expected" ]] && ok=1 ;;
        contains) [[ "$actual" == *"$expected"* ]] && ok=1 ;;
    esac
    if [[ "$ok" -eq 1 ]]; then
        PASSED=$((PASSED + 1))
        echo "  ${GREEN}PASS${RESET}  $name"
    else
        FAILED=$((FAILED + 1))
        echo "  ${RED}FAIL${RESET}  $name"
        echo "        actual=$actual  op=$op  expected=$expected"
    fi
}

jq_count() {
    local input="$1"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$input" | jq -r '.count // 0' 2>/dev/null
    else
        printf '%s' "$input" | grep -oE '"count":[0-9]+' | head -n 1 | cut -d: -f2
    fi
}

echo "== detect-stubs.sh =="
out="$(bash scripts/detect-stubs.sh tests/fixtures/project-with-stubs --json)"
n="$(jq_count "$out")"
assert "stubs in with-stubs >= 5" "$n" ">=" 5
out_clean="$(bash scripts/detect-stubs.sh tests/fixtures/project-clean --json)"
n_clean="$(jq_count "$out_clean")"
assert "stubs in clean == 0" "$n_clean" "==" 0

echo "== detect-empty-functions.py =="
out_ef="$(python3 scripts/detect-empty-functions.py tests/fixtures/project-with-stubs/empty.py --json)"
n_ef="$(jq_count "$out_ef")"
assert "empty fns >= 5" "$n_ef" ">=" 5

out_ef_clean="$(python3 scripts/detect-empty-functions.py tests/fixtures/project-clean --json)"
n_ef_clean="$(jq_count "$out_ef_clean")"
assert "empty fns clean == 0" "$n_ef_clean" "==" 0

echo "== detect-suspicious-returns.py =="
out_sr="$(python3 scripts/detect-suspicious-returns.py tests/fixtures/project-with-stubs/empty.py --json)"
n_sr="$(jq_count "$out_sr")"
assert "suspicious returns >= 2" "$n_sr" ">=" 2

echo "== detect-test-tautology.py =="
out_tt="$(python3 scripts/detect-test-tautology.py tests/fixtures/project-with-stubs --json)"
n_tt="$(jq_count "$out_tt")"
assert "tautologies in fake.test.js >= 3" "$n_tt" ">=" 3

out_tt_broken="$(python3 scripts/detect-test-tautology.py tests/fixtures/project-broken-tests --json)"
n_tt_broken="$(jq_count "$out_tt_broken")"
assert "tautologies in broken-tests >= 2" "$n_tt_broken" ">=" 2

out_tt_clean="$(python3 scripts/detect-test-tautology.py tests/fixtures/project-clean --json)"
n_tt_clean="$(jq_count "$out_tt_clean")"
assert "tautologies clean == 0" "$n_tt_clean" "==" 0

echo "== check-not-implemented.sh =="
out_ni="$(bash scripts/check-not-implemented.sh tests/fixtures/project-with-stubs --json)"
n_ni="$(jq_count "$out_ni")"
assert "not-implemented >= 3" "$n_ni" ">=" 3

echo "== detect-todos.sh =="
# detect-todos requires a git repo. Use the current one and just sanity-run.
out_todos="$(bash scripts/detect-todos.sh --json 2>/dev/null || true)"
assert "detect-todos returns JSON object" "$out_todos" "contains" '"count"'

echo "== run-full-suite.sh =="
out_rs="$(bash scripts/run-full-suite.sh --quiet 2>/dev/null || true)"
assert "run-full-suite returns JSON object" "$out_rs" "contains" '"runner"'

echo "== coverage-delta.sh =="
out_cov="$(bash scripts/coverage-delta.sh 2>/dev/null || true)"
assert "coverage-delta returns JSON object" "$out_cov" "contains" '"runner"'

echo "== JS-stubs fixture =="
out_js_stubs="$(bash scripts/detect-stubs.sh tests/fixtures/project-js-stubs --json)"
n_js_stubs="$(jq_count "$out_js_stubs")"
assert "JS stubs >= 3" "$n_js_stubs" ">=" 3

out_js_taut="$(python3 scripts/detect-test-tautology.py tests/fixtures/project-js-stubs --json)"
n_js_taut="$(jq_count "$out_js_taut")"
assert "JS test-tautology >= 6" "$n_js_taut" ">=" 6
assert "JS catches expect.assertions(0)" "$out_js_taut" contains "expect.assertions(0)"
assert "JS catches toMatchSnapshot empty" "$out_js_taut" contains "toMatchSnapshot"
assert "JS catches toHaveBeenCalled lone" "$out_js_taut" contains "toHaveBeenCalled"

echo "== Go-stubs fixture =="
out_go_stubs="$(bash scripts/detect-stubs.sh tests/fixtures/project-go-stubs --json)"
n_go_stubs="$(jq_count "$out_go_stubs")"
assert "Go stubs >= 4" "$n_go_stubs" ">=" 4
assert "Go nolint detected" "$out_go_stubs" contains "go_nolint"

out_go_sr="$(python3 scripts/detect-suspicious-returns.py tests/fixtures/project-go-stubs --json)"
n_go_sr="$(jq_count "$out_go_sr")"
assert "Go suspicious-returns >= 3" "$n_go_sr" ">=" 3
assert "Go uninitialized constructor flagged" "$out_go_sr" contains "uninitialized_constructor"
assert "Go error-swallow flagged" "$out_go_sr" contains "error_swallow"

out_go_taut="$(python3 scripts/detect-test-tautology.py tests/fixtures/project-go-stubs --json)"
n_go_taut="$(jq_count "$out_go_taut")"
assert "Go test-tautology >= 4" "$n_go_taut" ">=" 4
assert "Go test_no_assertion flagged" "$out_go_taut" contains "test_no_assertion"
assert "Go test_skipped flagged" "$out_go_taut" contains "test_skipped"
assert "Go test_todo_log flagged" "$out_go_taut" contains "test_todo_log"

echo "== scope.roots monorepo =="
# Fixture project-monorepo has app/dirty.py (in scope) and vendor-thing/very_dirty.py
# (out of scope, behind scope.roots=["app/"]).
MONO_DIR="tests/fixtures/project-monorepo"

# With scope honored (default): only app/ is scanned.
out_scope_stubs="$(cd "$MONO_DIR" && bash "$ROOT/scripts/detect-stubs.sh" --all --json)"
n_scope_stubs="$(jq_count "$out_scope_stubs")"
assert "scope.roots filters detect-stubs --all to app/" "$n_scope_stubs" "==" 2

# DODG_NO_SCOPE=1 disables scope filtering: both directories visible.
out_noscope_stubs="$(cd "$MONO_DIR" && DODG_NO_SCOPE=1 bash "$ROOT/scripts/detect-stubs.sh" --all --json)"
n_noscope_stubs="$(jq_count "$out_noscope_stubs")"
assert "DODG_NO_SCOPE=1 disables stub scope filtering" "$n_noscope_stubs" ">=" 6

# Python detector honors scope when called with '.'.
out_scope_ef="$(cd "$MONO_DIR" && python3 "$ROOT/scripts/detect-empty-functions.py" . --json)"
n_scope_ef="$(jq_count "$out_scope_ef")"
assert "scope.roots filters detect-empty-functions to app/" "$n_scope_ef" "==" 2

# Without scope: detect-empty-functions sees all 6 trivial bodies.
out_noscope_ef="$(cd "$MONO_DIR" && DODG_NO_SCOPE=1 python3 "$ROOT/scripts/detect-empty-functions.py" . --json)"
n_noscope_ef="$(jq_count "$out_noscope_ef")"
assert "DODG_NO_SCOPE=1 disables Python detector scope" "$n_noscope_ef" ">=" 6

# path_in_scope helper: lets --diff modes silently drop out-of-scope files.
in_scope_result="$(cd "$MONO_DIR" && \
    bash -c 'source "$1/scripts/lib/languages.sh"; path_in_scope "app/dirty.py" && echo IN || echo OUT' _ "$ROOT")"
assert "path_in_scope: in-scope file" "$in_scope_result" "==" "IN"

out_scope_result="$(cd "$MONO_DIR" && \
    bash -c 'source "$1/scripts/lib/languages.sh"; path_in_scope "vendor-thing/very_dirty.py" && echo IN || echo OUT' _ "$ROOT")"
assert "path_in_scope: out-of-scope file" "$out_scope_result" "==" "OUT"

no_scope_result="$(cd tests/fixtures/project-clean && \
    bash -c 'source "$1/scripts/lib/languages.sh"; path_in_scope "anywhere/file.py" && echo IN || echo OUT' _ "$ROOT")"
assert "path_in_scope: no scope configured = everything in" "$no_scope_result" "==" "IN"

echo "== run-verification-pipeline.sh =="
# Run inside the with-stubs fixture so we see a real FAIL verdict.
pushd tests/fixtures/project-with-stubs >/dev/null || exit 2
out_pipe="$(bash ../../../scripts/run-verification-pipeline.sh --skip-tests --json 2>/dev/null || true)"
popd >/dev/null || exit 2
assert "pipeline emits verdict" "$out_pipe" "contains" '"verdict"'
assert "pipeline verdict=FAIL on stubs fixture" "$out_pipe" "contains" '"FAIL"'

echo ""
echo "------------------------------------------------------------"
echo "  ${PASSED} passed, ${FAILED} failed"
echo "------------------------------------------------------------"
if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
