#!/usr/bin/env bash
# scripts/run-full-suite.sh
# Detect the project's test runner, run it, and emit a structured JSON record.
#
# Usage: run-full-suite.sh [--quiet]
# Exit codes mirror the runner's: 0 = pass, 1+ = fail. 2 = no runner detected.

set -uo pipefail

QUIET=0
for arg in "$@"; do
    case "$arg" in
        --quiet) QUIET=1 ;;
        --help|-h)
            sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
    esac
done

now_ms() { python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || date +%s%3N; }

detect_runner() {
    if [[ -f "pyproject.toml" || -f "pytest.ini" || -f "setup.cfg" ]] && command -v pytest >/dev/null 2>&1; then
        echo "pytest"; return
    fi
    if [[ -f "package.json" ]]; then
        if grep -q '"test":' package.json 2>/dev/null; then
            if grep -q '"jest"' package.json 2>/dev/null; then echo "jest"; return; fi
            if grep -q '"vitest"' package.json 2>/dev/null; then echo "vitest"; return; fi
            echo "npm-test"; return
        fi
    fi
    if [[ -f "go.mod" ]] && command -v go >/dev/null 2>&1; then
        echo "go"; return
    fi
    if [[ -f "Cargo.toml" ]] && command -v cargo >/dev/null 2>&1; then
        echo "cargo"; return
    fi
    echo "unknown"
}

# JSON-escape stdin to stdout.
json_escape_stdin() {
    python3 -c 'import json,sys;sys.stdout.write(json.dumps(sys.stdin.read()))'
}

runner="$(detect_runner)"
if [[ "$runner" == "unknown" ]]; then
    printf '{"runner":"unknown","passed":0,"failed":0,"skipped":0,"duration_ms":0,"raw_output":"","reason":"runner_not_detected"}\n'
    exit 2
fi

start="$(now_ms)"
case "$runner" in
    pytest)   cmd=(pytest -v --tb=short --color=no) ;;
    jest)     cmd=(npx --no-install jest --colors=false) ;;
    vitest)   cmd=(npx --no-install vitest run --reporter=verbose) ;;
    npm-test) cmd=(npm test --silent) ;;
    go)       cmd=(go test ./...) ;;
    cargo)    cmd=(cargo test --quiet) ;;
esac

if [[ "$QUIET" -eq 1 ]]; then
    raw="$("${cmd[@]}" 2>&1 || true)"
    rc=$?
else
    # Tee the output so the human sees progress.
    raw="$("${cmd[@]}" 2>&1 | tee /dev/stderr; exit "${PIPESTATUS[0]}")" || rc=$?
    rc=${rc:-0}
fi
end="$(now_ms)"

# Parse summary counts by runner.
passed=0; failed=0; skipped=0
case "$runner" in
    pytest)
        # "12 passed, 1 failed, 2 skipped in 1.23s"
        passed=$(grep -oE '[0-9]+ passed'   <<<"$raw" | tail -n 1 | awk '{print $1}' || echo 0)
        failed=$(grep -oE '[0-9]+ failed'   <<<"$raw" | tail -n 1 | awk '{print $1}' || echo 0)
        skipped=$(grep -oE '[0-9]+ skipped' <<<"$raw" | tail -n 1 | awk '{print $1}' || echo 0)
        ;;
    jest|vitest)
        passed=$(grep -oE 'Tests?:[^,]*[0-9]+ passed' <<<"$raw" | grep -oE '[0-9]+' | tail -n 1 || echo 0)
        failed=$(grep -oE '[0-9]+ failed' <<<"$raw" | grep -oE '[0-9]+' | tail -n 1 || echo 0)
        skipped=$(grep -oE '[0-9]+ skipped' <<<"$raw" | grep -oE '[0-9]+' | tail -n 1 || echo 0)
        ;;
    go)
        passed=$(grep -cE '^--- PASS' <<<"$raw" || true)
        failed=$(grep -cE '^--- FAIL' <<<"$raw" || true)
        skipped=$(grep -cE '^--- SKIP' <<<"$raw" || true)
        ;;
    cargo)
        passed=$(grep -oE 'test result:.*[0-9]+ passed' <<<"$raw" | grep -oE '[0-9]+' | head -n 1 || echo 0)
        failed=$(grep -oE 'test result:.*[0-9]+ failed' <<<"$raw" | grep -oE '[0-9]+' | tail -n 1 || echo 0)
        skipped=$(grep -oE 'test result:.*[0-9]+ ignored' <<<"$raw" | grep -oE '[0-9]+' | tail -n 1 || echo 0)
        ;;
esac

passed=${passed:-0}; failed=${failed:-0}; skipped=${skipped:-0}
duration=$((end - start))

raw_json="$(printf '%s' "$raw" | json_escape_stdin)"
printf '{"runner":"%s","passed":%s,"failed":%s,"skipped":%s,"duration_ms":%s,"exit_code":%s,"raw_output":%s}\n' \
    "$runner" "$passed" "$failed" "$skipped" "$duration" "$rc" "$raw_json"

exit "$rc"
