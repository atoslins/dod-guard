#!/usr/bin/env bash
# scripts/detect-todos.sh
# Fast scan for TODO/FIXME/XXX/HACK markers in the current git diff.
#
# Usage: detect-todos.sh [--json|--text]
# Exit codes: 0 = no markers, 1 = markers found, 2 = invocation error.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/report.sh disable=SC1091
source "$SCRIPT_DIR/lib/report.sh"

OUTPUT_FORMAT="json"
case "${1:-}" in
    --text) OUTPUT_FORMAT="text" ;;
    --json|"") OUTPUT_FORMAT="json" ;;
    --help|-h)
        sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "detect-todos: unknown argument '$1'" >&2
        exit 2
        ;;
esac

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "detect-todos: not inside a git repository" >&2
    exit 2
fi

report_init

# Emit "<file>\t<lineno>\t<content>" for every added line that matches.
# Awk handles file/line tracking from the unified diff stream.
scan_diff_to_tsv() {
    local args=("$@")
    git diff -U0 "${args[@]}" 2>/dev/null | awk '
        /^diff --git/ {
            n = split($0, a, " b/")
            file = a[n]
            next
        }
        /^@@ / {
            # Extract new-side starting line from "@@ -X,Y +A,B @@".
            if (match($0, /\+[0-9]+/)) {
                line = substr($0, RSTART+1, RLENGTH-1) + 0
            }
            next
        }
        /^\+\+\+/ { next }
        /^\+/ {
            content = substr($0, 2)
            if (content ~ /(TODO|FIXME|XXX|HACK)([[:space:]:]|$)/) {
                printf "%s\t%d\t%s\n", file, line, content
            }
            # nolint markers added in the diff are escape-hatches and worth surfacing.
            else if (content ~ /\/\/[[:space:]]*nolint(:|$)/) {
                printf "%s\t%d\tNOLINT %s\n", file, line, content
            }
            line++
        }
    '
}

# Use process substitution so report_issue updates stay in the parent shell.
while IFS=$'\t' read -r file lineno content; do
    [[ -z "$file" ]] && continue
    sev=warn
    case "$content" in
        *TODO*|*FIXME*) sev=high ;;
    esac
    report_issue "$file" "$lineno" "todo_marker" "$content" "$sev"
done < <( { scan_diff_to_tsv; scan_diff_to_tsv --cached; } | sort -u )

count="$(report_count)"
if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    report_text_summary
else
    report_finalize "Scanned current diff"
fi

if [[ "$count" -gt 0 ]]; then
    exit 1
fi
exit 0
