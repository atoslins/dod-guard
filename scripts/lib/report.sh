#!/usr/bin/env bash
# scripts/lib/report.sh
# JSON issue accumulator. Source this file; do not execute directly.
#
# Exposes:
#   report_init                                              - clears any previous accumulator
#   report_issue <file> <line> <type> <evidence> <severity>  - appends an issue
#   report_count                                             - prints the current issue count
#   report_finalize [summary]                                - prints the final JSON
#
# Severity values: info | warn | high | block

set -uo pipefail

# Holds issue objects as a JSON array string. Default = empty array.
DODG_REPORT_ISSUES='[]'

report_init() {
    DODG_REPORT_ISSUES='[]'
}

# Strip surrounding whitespace and JSON-escape a string. Pure bash, no jq
# dependency, so this script remains usable in tightly sandboxed hooks.
_dodg_json_escape() {
    local s="$1"
    # Replace literal characters that break JSON: backslash first, then quote.
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\n'/\\n}"
    printf '%s' "$s"
}

# Append an issue. All arguments are required.
report_issue() {
    local file="$1" line="$2" type="$3" evidence="$4" severity="$5"
    local file_e type_e evidence_e severity_e
    file_e="$(_dodg_json_escape "$file")"
    type_e="$(_dodg_json_escape "$type")"
    evidence_e="$(_dodg_json_escape "$evidence")"
    severity_e="$(_dodg_json_escape "$severity")"

    local entry
    entry="{\"file\":\"$file_e\",\"line\":$line,\"type\":\"$type_e\",\"evidence\":\"$evidence_e\",\"severity\":\"$severity_e\"}"

    if [[ "$DODG_REPORT_ISSUES" == "[]" ]]; then
        DODG_REPORT_ISSUES="[$entry]"
    else
        DODG_REPORT_ISSUES="${DODG_REPORT_ISSUES%]},$entry]"
    fi
}

# Count of accumulated issues. Uses jq if available; otherwise counts manually.
report_count() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$DODG_REPORT_ISSUES" | jq 'length'
    else
        # Fallback: count entries by occurrences of `"file":`.
        local n
        n="$(printf '%s' "$DODG_REPORT_ISSUES" | grep -o '"file":' | wc -l | tr -d '[:space:]')"
        printf '%s' "$n"
    fi
}

# Print the final JSON document. Optional first arg = human summary.
report_finalize() {
    local summary="${1:-}"
    local count summary_e
    count="$(report_count)"
    summary_e="$(_dodg_json_escape "$summary")"
    printf '{"count":%s,"issues":%s,"summary":"%s"}\n' \
        "$count" "$DODG_REPORT_ISSUES" "$summary_e"
}

# Convenience: print human-readable text summary instead of JSON.
report_text_summary() {
    local count
    count="$(report_count)"
    echo "Found $count issue(s)."
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$DODG_REPORT_ISSUES" | jq -r '.[] | "  \(.severity | ascii_upcase)  \(.file):\(.line)  [\(.type)]  \(.evidence)"'
    fi
}
