#!/usr/bin/env bash
# scripts/detect-stubs.sh
# Detect stub markers across the project, a single file, or the current diff.
#
# Usage:
#   detect-stubs.sh <file>                  scan one file
#   detect-stubs.sh <directory>             scan a tree
#   detect-stubs.sh --all                   scan the whole project root
#   detect-stubs.sh --diff                  scan only files in current git diff
#   detect-stubs.sh ... --json|--text       output format (default: json)
#
# Reads .dod-guard.json (if present in CWD) for project-specific patterns.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/languages.sh disable=SC1091
source "$SCRIPT_DIR/lib/languages.sh"
# shellcheck source=lib/report.sh disable=SC1091
source "$SCRIPT_DIR/lib/report.sh"

# Default stub patterns. Override via .dod-guard.json -> detectors.stubs.patterns.
# Each entry is "type::regex::severity".
DEFAULT_PATTERNS=(
    'todo_marker::TODO[[:space:]:]::high'
    'fixme_marker::FIXME[[:space:]:]::high'
    'xxx_marker::XXX[[:space:]:]::warn'
    'hack_marker::HACK[[:space:]:]::warn'
    'not_implemented_py::raise NotImplementedError::high'
    'not_implemented_go::panic\("not[[:space:]]implemented::high'
    'not_implemented_rust::(todo!|unimplemented!)\(::high'
    'not_implemented_js::throw new Error\(["'"'"']not implemented::high'
    'placeholder_string::"placeholder"::warn'
    'ellipsis_python_body::^[[:space:]]+\.\.\.[[:space:]]*$::warn'
    'go_nolint::^[[:space:]]*//[[:space:]]*nolint(:|$)::warn'
)

OUTPUT_FORMAT="json"
TARGET=""
MODE="path"
declare -a TARGETS=()

# Parse args.
for arg in "$@"; do
    case "$arg" in
        --json) OUTPUT_FORMAT="json" ;;
        --text) OUTPUT_FORMAT="text" ;;
        --all)  MODE="all" ;;
        --diff) MODE="diff" ;;
        --help|-h)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) TARGET="$arg" ;;
    esac
done

# Load custom patterns from .dod-guard.json if present.
declare -a PATTERNS=()
if [[ -f ".dod-guard.json" ]] && command -v jq >/dev/null 2>&1; then
    if jq -e '.detectors.stubs.patterns' .dod-guard.json >/dev/null 2>&1; then
        while IFS= read -r line; do
            PATTERNS+=("$line")
        done < <(jq -r '.detectors.stubs.patterns[] | "\(.type)::\(.regex)::\(.severity)"' .dod-guard.json)
    fi
fi
if [[ ${#PATTERNS[@]} -eq 0 ]]; then
    PATTERNS=("${DEFAULT_PATTERNS[@]}")
fi

# Build the list of files to scan.
collect_targets() {
    case "$MODE" in
        all)
            while IFS= read -r f; do TARGETS+=("$f"); done < <(walk_source_files ".")
            ;;
        diff)
            if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                echo "detect-stubs: --diff requires a git repository" >&2
                exit 2
            fi
            local list
            list="$( { git diff --name-only --diff-filter=AM; git diff --name-only --cached --diff-filter=AM; } | sort -u )"
            while IFS= read -r f; do
                [[ -z "$f" ]] && continue
                [[ -f "$f" ]] || continue
                # Respect scope.roots: silently drop files outside the configured scope.
                path_in_scope "$f" || continue
                TARGETS+=("$f")
            done <<< "$list"
            ;;
        path)
            if [[ -z "$TARGET" ]]; then
                echo "detect-stubs: pass a file, a directory, --all, or --diff" >&2
                exit 2
            fi
            if [[ -d "$TARGET" ]]; then
                while IFS= read -r f; do TARGETS+=("$f"); done < <(walk_source_files "$TARGET")
            elif [[ -f "$TARGET" ]]; then
                TARGETS+=("$TARGET")
            else
                echo "detect-stubs: path not found: $TARGET" >&2
                exit 2
            fi
            ;;
    esac
}

scan_one() {
    local file="$1"
    local lang
    lang="$(detect_language "$file")"
    [[ "$lang" == "unknown" ]] && return 0

    local entry type regex severity
    for entry in "${PATTERNS[@]}"; do
        type="${entry%%::*}"
        local rest="${entry#*::}"
        regex="${rest%::*}"
        severity="${rest##*::}"

        # Use grep -E (POSIX ERE) with line numbers. Suppress errors on binary files.
        while IFS= read -r match; do
            [[ -z "$match" ]] && continue
            local lineno content
            lineno="${match%%:*}"
            content="${match#*:}"
            # Skip matches inside string literals that are clearly comments-only.
            # (We keep this lenient — false positives are tolerated; missed stubs are not.)
            report_issue "$file" "$lineno" "$type" "$content" "$severity"
        done < <(grep -nE -- "$regex" "$file" 2>/dev/null | head -n 100)
    done
}

report_init
collect_targets
for f in "${TARGETS[@]}"; do
    scan_one "$f"
done

if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    report_text_summary
else
    report_finalize "Scanned ${#TARGETS[@]} file(s)"
fi
