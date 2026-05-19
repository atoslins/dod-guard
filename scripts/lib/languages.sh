#!/usr/bin/env bash
# scripts/lib/languages.sh
# Language detection utilities. Source this file; do not execute directly.
#
# Exposes:
#   detect_language <path>     - prints one of: python|node|typescript|go|rust|ruby|bash|java|kotlin|csharp|unknown
#   list_source_extensions     - prints the regex of recognized source extensions
#   is_test_file <path>        - returns 0 if the path matches a test-file convention
#   walk_source_files <root>   - prints absolute paths of recognized source files under <root>

set -uo pipefail

# Detect language from extension first, fall back to shebang inspection for
# extensionless or ambiguous files.
detect_language() {
    local path="$1"
    local base ext
    base="$(basename -- "$path")"
    ext="${base##*.}"
    # If "ext == base" then there was no dot in the name.
    if [[ "$ext" == "$base" ]]; then
        ext=""
    fi
    ext="${ext,,}"

    case "$ext" in
        py)            echo "python"     ; return ;;
        js|cjs|mjs|jsx) echo "node"      ; return ;;
        ts|tsx)        echo "typescript" ; return ;;
        go)            echo "go"         ; return ;;
        rs)            echo "rust"       ; return ;;
        rb)            echo "ruby"       ; return ;;
        sh|bash)       echo "bash"       ; return ;;
        java)          echo "java"       ; return ;;
        kt|kts)        echo "kotlin"     ; return ;;
        cs)            echo "csharp"     ; return ;;
    esac

    # Fall back to shebang.
    if [[ -r "$path" ]]; then
        local first
        first="$(head -n 1 -- "$path" 2>/dev/null || true)"
        case "$first" in
            *python*) echo "python" ; return ;;
            *node*)   echo "node"   ; return ;;
            *bash*|*sh*) echo "bash" ; return ;;
            *ruby*)   echo "ruby"   ; return ;;
        esac
    fi

    echo "unknown"
}

# Regex of recognized source extensions (used with find).
list_source_extensions() {
    echo '\.\(py\|js\|cjs\|mjs\|jsx\|ts\|tsx\|go\|rs\|rb\|sh\|bash\|java\|kt\|kts\|cs\)$'
}

# Heuristic: file path matches a known test-file convention.
is_test_file() {
    local path="$1"
    local base
    base="$(basename -- "$path")"
    case "$base" in
        test_*.py|*_test.py|tests_*.py|*.test.ts|*.test.tsx|*.test.js|*.test.jsx) return 0 ;;
        *_test.go|*_spec.rb|*Test.java|*Tests.cs|*.spec.ts|*.spec.js) return 0 ;;
    esac
    # Path-based: inside a tests/, test/, or __tests__/ directory.
    case "$path" in
        */tests/*|*/test/*|*/__tests__/*|*/spec/*) return 0 ;;
    esac
    return 1
}

# Walk source files under a directory, respecting common ignore dirs.
walk_source_files() {
    local root="${1:-.}"
    local ext_re
    ext_re="$(list_source_extensions)"
    find "$root" \
        \( -path '*/node_modules' -o \
           -path '*/.git' -o \
           -path '*/__pycache__' -o \
           -path '*/.venv' -o \
           -path '*/venv' -o \
           -path '*/target' -o \
           -path '*/dist' -o \
           -path '*/build' -o \
           -path '*/.dod-guard' \) -prune -o \
        -type f -regextype posix-basic -regex ".*$ext_re" -print
}
