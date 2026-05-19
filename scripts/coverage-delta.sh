#!/usr/bin/env bash
# scripts/coverage-delta.sh
# Compute test-coverage delta versus the last baseline (.dod-guard/baseline.json).
#
# Detects the runner: pytest+coverage, npm/jest, go test -cover. Best-effort.
# When the runner cannot be detected or coverage extraction fails, the script
# still exits 0 and emits a JSON record with reason="runner_unknown" or
# reason="coverage_extraction_failed" so callers can branch on it.
#
# Usage: coverage-delta.sh [--update-baseline]

set -uo pipefail

UPDATE_BASELINE=0
for arg in "$@"; do
    case "$arg" in
        --update-baseline) UPDATE_BASELINE=1 ;;
        --help|-h)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
    esac
done

BASELINE_FILE=".dod-guard/baseline.json"
mkdir -p .dod-guard

detect_runner() {
    if [[ -f "pyproject.toml" || -f "pytest.ini" || -d "tests" ]] && command -v pytest >/dev/null 2>&1; then
        echo "pytest"
        return
    fi
    if [[ -f "package.json" ]]; then
        if grep -q '"jest"' package.json 2>/dev/null; then
            echo "jest"; return
        fi
        if grep -q '"vitest"' package.json 2>/dev/null; then
            echo "vitest"; return
        fi
    fi
    if [[ -f "go.mod" ]] && command -v go >/dev/null 2>&1; then
        echo "go"
        return
    fi
    echo "unknown"
}

extract_coverage() {
    local runner="$1"
    local pct=""
    case "$runner" in
        pytest)
            if pytest --cov=. --cov-report= -q >/tmp/dodg_cov.log 2>&1; then
                pct="$(grep -oE 'TOTAL[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9.]+%' /tmp/dodg_cov.log | awk '{print $NF}' | tr -d '%')"
            fi
            ;;
        jest)
            if npx --no-install jest --coverage --silent >/tmp/dodg_cov.log 2>&1; then
                pct="$(grep -oE 'All files[^|]*\|[[:space:]]*[0-9.]+' /tmp/dodg_cov.log | awk -F'|' '{print $2}' | tr -d ' ')"
            fi
            ;;
        vitest)
            if npx --no-install vitest run --coverage >/tmp/dodg_cov.log 2>&1; then
                pct="$(grep -oE 'All files[^|]*\|[[:space:]]*[0-9.]+' /tmp/dodg_cov.log | awk -F'|' '{print $2}' | tr -d ' ')"
            fi
            ;;
        go)
            if go test ./... -cover 2>/dev/null | tee /tmp/dodg_cov.log | grep -oE 'coverage: [0-9.]+%' >/dev/null; then
                pct="$(grep -oE 'coverage: [0-9.]+%' /tmp/dodg_cov.log | awk '{print $2}' | tr -d '%' | tail -n 1)"
            fi
            ;;
    esac
    if [[ -z "$pct" ]]; then
        return 1
    fi
    printf '%s' "$pct"
}

runner="$(detect_runner)"
if [[ "$runner" == "unknown" ]]; then
    printf '{"runner":"unknown","current":null,"baseline":null,"delta":null,"reason":"runner_unknown"}\n'
    exit 0
fi

current="$(extract_coverage "$runner" 2>/dev/null || true)"
if [[ -z "$current" ]]; then
    printf '{"runner":"%s","current":null,"baseline":null,"delta":null,"reason":"coverage_extraction_failed"}\n' "$runner"
    exit 0
fi

baseline=""
if [[ -f "$BASELINE_FILE" ]] && command -v jq >/dev/null 2>&1; then
    baseline="$(jq -r '.coverage // empty' "$BASELINE_FILE" 2>/dev/null || true)"
fi

delta=""
if [[ -n "$baseline" ]]; then
    delta="$(awk -v a="$current" -v b="$baseline" 'BEGIN { printf "%.2f", a - b }')"
fi

if [[ "$UPDATE_BASELINE" -eq 1 ]]; then
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg runner "$runner" --arg cov "$current" \
            '{runner: $runner, coverage: ($cov|tonumber), updated_at: now|todate}' \
            > "$BASELINE_FILE"
    else
        printf '{"runner":"%s","coverage":%s}\n' "$runner" "$current" > "$BASELINE_FILE"
    fi
fi

if [[ -z "$baseline" ]]; then
    printf '{"runner":"%s","current":%s,"baseline":null,"delta":null,"reason":"no_baseline"}\n' \
        "$runner" "$current"
else
    printf '{"runner":"%s","current":%s,"baseline":%s,"delta":%s}\n' \
        "$runner" "$current" "$baseline" "$delta"
fi
