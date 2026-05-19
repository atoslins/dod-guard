#!/usr/bin/env bash
# hooks/handlers/post-edit.sh
# PostToolUse hook for Write|Edit|MultiEdit|NotebookEdit.
#
# Behavior:
#   - No DoD config in the project → exit 0.
#   - File extension not in the source set → exit 0.
#   - Run detect-stubs on the edited file. Severity-aware:
#       severity == block in config → emit {"decision":"block","reason":...}
#       severity == warn          → emit a non-blocking warning message
#
# Input JSON (stdin): { "tool_input": { "file_path": "<abs path>" }, ... }
# Output JSON (stdout): conforms to Claude Code's PostToolUse contract.

set -uo pipefail

PLUGIN_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/../.. && pwd)"
SCRIPT_DIR="$PLUGIN_ROOT/scripts"

# Read the entire payload from stdin.
payload="$(cat || true)"

# Bail if .dod-guard.json absent (no-op for projects that haven't opted in).
if [[ ! -f ".dod-guard.json" ]]; then
    exit 0
fi

# Extract the edited file path. The tool may emit Unix or Windows paths.
file_path=""
if command -v jq >/dev/null 2>&1; then
    file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)"
fi
if [[ -z "$file_path" ]]; then
    # Fallback for jq-less environments.
    file_path="$(printf '%s' "$payload" | grep -oE '"file_path"\s*:\s*"[^"]+"' | head -n 1 | sed -E 's/.*"file_path"\s*:\s*"([^"]+)".*/\1/' || true)"
fi

# If the file no longer exists (the edit may have been a delete), bail.
if [[ -z "$file_path" || ! -f "$file_path" ]]; then
    exit 0
fi

# Severity policy from config. Default: "warn".
severity_policy="warn"
if command -v jq >/dev/null 2>&1; then
    sp="$(jq -r '.hooks.post_edit.severity // empty' .dod-guard.json 2>/dev/null || true)"
    [[ -n "$sp" ]] && severity_policy="$sp"
fi

# Run the stub detector on the single file.
report="$(bash "$SCRIPT_DIR/detect-stubs.sh" "$file_path" --json 2>/dev/null || true)"
count=0
if command -v jq >/dev/null 2>&1; then
    count="$(printf '%s' "$report" | jq -r '.count // 0' 2>/dev/null || echo 0)"
fi
count=${count:-0}

if [[ "$count" -eq 0 ]]; then
    exit 0
fi

# Build a concise reason. The orchestrator sees this verbatim.
reason="DoD-Guard: $count issue(s) detected in $file_path after edit."
if command -v jq >/dev/null 2>&1; then
    bullets="$(printf '%s' "$report" | jq -r '.issues[:5][] | "  - [\(.severity)] line \(.line)  \(.type): \(.evidence)"' 2>/dev/null || true)"
    if [[ -n "$bullets" ]]; then
        reason+=$'\n'"$bullets"
    fi
fi
reason+=$'\n'"Fix these before continuing. Run /dod:stubs for a full list."

case "$severity_policy" in
    block)
        python3 - "$reason" <<'PYEOF'
import json, sys
print(json.dumps({"decision": "block", "reason": sys.argv[1]}))
PYEOF
        exit 0
        ;;
    warn|*)
        # Non-blocking informational message — passed via systemMessage.
        python3 - "$reason" <<'PYEOF'
import json, sys
print(json.dumps({"systemMessage": sys.argv[1]}))
PYEOF
        exit 0
        ;;
esac
