#!/usr/bin/env bash
# scripts/check-not-implemented.sh
# Fast grep for "not implemented" markers across all source files.
#
# Usage: check-not-implemented.sh [<root>] [--json|--text]
# Exit codes: 0 = none found, 1 = some found, 2 = invocation error.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/report.sh
source "$SCRIPT_DIR/lib/report.sh"
# shellcheck source=lib/languages.sh
source "$SCRIPT_DIR/lib/languages.sh"

ROOT="."
OUTPUT_FORMAT="json"
for arg in "$@"; do
    case "$arg" in
        --json) OUTPUT_FORMAT="json" ;;
        --text) OUTPUT_FORMAT="text" ;;
        --help|-h)
            sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) ROOT="$arg" ;;
    esac
done

if [[ ! -d "$ROOT" && ! -f "$ROOT" ]]; then
    echo "check-not-implemented: root not found: $ROOT" >&2
    exit 2
fi

report_init

PATTERNS=(
    'raise NotImplementedError'
    'NotImplementedError'
    'panic\("not implemented'
    'panic\("unimplemented'
    'todo!\(\)'
    'unimplemented!\(\)'
    'throw new Error\(["'"'"']not implemented'
    'TODO: implement'
)

scan_root() {
    local root="$1"
    if [[ -f "$root" ]]; then
        printf '%s\n' "$root"
    else
        walk_source_files "$root"
    fi
}

while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    for pat in "${PATTERNS[@]}"; do
        while IFS=: read -r lineno content; do
            [[ -z "$lineno" ]] && continue
            report_issue "$file" "$lineno" "not_implemented" "$content" "high"
        done < <(grep -nE -- "$pat" "$file" 2>/dev/null | head -n 100)
    done
done < <(scan_root "$ROOT")

count="$(report_count)"
if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    report_text_summary
else
    report_finalize "Scanned $ROOT"
fi

if [[ "$count" -gt 0 ]]; then
    exit 1
fi
exit 0
