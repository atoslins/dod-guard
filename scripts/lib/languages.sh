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

# Load scope.roots from .dod-guard.json (whole-project monorepo scoping).
# Echoes one root per line; empty output means "no scoping configured".
# DODG_NO_SCOPE=1 in the env disables scope loading (parity with DODG_NO_EXEMPTIONS).
load_scope_roots() {
    [[ -n "${DODG_NO_SCOPE:-}" ]] && return 0
    [[ -f ".dod-guard.json" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r '.scope.roots // [] | .[] | select(. != null and . != "")' .dod-guard.json 2>/dev/null
}

# Walk source files under a directory, respecting common ignore dirs and the
# project's .dod-guard.json `exemptions.paths` globs (if jq is available).
#
# When called with root='.' AND .dod-guard.json defines `scope.roots`, walk
# each configured root instead of the entire cwd. Explicit non-'.' roots are
# honored as-is so callers passing a specific path (a single file, a fixture
# dir) keep their behavior.
walk_source_files() {
    local root="${1:-.}"
    local ext_re
    ext_re="$(list_source_extensions)"

    # Cache the exemption globs once per call, then filter the find output.
    # DODG_NO_EXEMPTIONS=1 in the env disables exemption loading (used by tests).
    local exempt_globs=()
    if [[ -z "${DODG_NO_EXEMPTIONS:-}" ]] && [[ -f ".dod-guard.json" ]] && command -v jq >/dev/null 2>&1; then
        while IFS= read -r g; do
            [[ -n "$g" ]] && exempt_globs+=("$g")
        done < <(jq -r '.exemptions.paths // [] | .[]' .dod-guard.json 2>/dev/null)
    fi

    is_exempt_path() {
        local p="$1" glob
        # Strip leading ./ for consistent matching.
        p="${p#./}"
        for glob in "${exempt_globs[@]}"; do
            # bash glob with extglob doesn't quite match .gitignore semantics,
            # but for the common case "**/dir/**" we can translate to a substring
            # check. For anything else, fall back to direct globbing.
            if [[ "$glob" == "**/"*"/**" ]]; then
                local inner="${glob#**/}"; inner="${inner%/**}"
                [[ "$p" == *"/$inner/"* || "$p" == "$inner/"* ]] && return 0
                continue
            fi
            # shellcheck disable=SC2053  # we want glob matching on RHS
            [[ "$p" == $glob ]] && return 0
        done
        return 1
    }

    # Resolve the actual search roots. Default is the caller-supplied root;
    # if the caller said "." and scope.roots is configured, expand to those.
    local search_roots=("$root")
    if [[ "$root" == "." || "$root" == "./" ]]; then
        local scope_roots=()
        while IFS= read -r r; do
            [[ -n "$r" ]] && scope_roots+=("$r")
        done < <(load_scope_roots)
        if [[ ${#scope_roots[@]} -gt 0 ]]; then
            search_roots=("${scope_roots[@]}")
        fi
    fi

    local search_root
    for search_root in "${search_roots[@]}"; do
        [[ -e "$search_root" ]] || continue
        while IFS= read -r f; do
            is_exempt_path "$f" && continue
            printf '%s\n' "$f"
        done < <(find "$search_root" \
            \( -path '*/node_modules' -o \
               -path '*/.git' -o \
               -path '*/__pycache__' -o \
               -path '*/.venv' -o \
               -path '*/venv' -o \
               -path '*/target' -o \
               -path '*/dist' -o \
               -path '*/build' -o \
               -path '*/.dod-guard' \) -prune -o \
            -type f -regextype posix-basic -regex ".*$ext_re" -print)
    done
}

# Print 0 if a given path falls under any configured scope.roots, 1 otherwise.
# If no scope.roots is configured, every path is considered in-scope (returns 0).
# Used by --diff modes to filter git-listed paths.
path_in_scope() {
    local p="$1" root
    p="${p#./}"
    local scope_roots=()
    while IFS= read -r root; do
        [[ -n "$root" ]] && scope_roots+=("$root")
    done < <(load_scope_roots)
    if [[ ${#scope_roots[@]} -eq 0 ]]; then
        return 0
    fi
    for root in "${scope_roots[@]}"; do
        root="${root%/}"
        [[ -z "$root" ]] && continue
        if [[ "$p" == "$root" || "$p" == "$root/"* ]]; then
            return 0
        fi
    done
    return 1
}
