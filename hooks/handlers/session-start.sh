#!/usr/bin/env bash
# hooks/handlers/session-start.sh
# SessionStart hook: load .dod-guard.json and DOD.md into the agent's context.
#
# Input JSON (on stdin):  Claude Code SessionStart payload (unused here).
# Output JSON (on stdout):
#   {"hookSpecificOutput": {"hookEventName": "SessionStart",
#                            "additionalContext": "<markdown block>"}}
#
# No-op (exit 0 with no output) when DoD-Guard is not configured in the cwd.

set -uo pipefail

# Discard stdin — we do not depend on the payload yet.
cat >/dev/null 2>&1 || true

CFG=".dod-guard.json"
DOD_FILE="DOD.md"

# Bail silently if the project is not DoD-guarded.
if [[ ! -f "$CFG" && ! -f "$DOD_FILE" ]]; then
    exit 0
fi

block=""
block+="## DoD-Guard is active in this project"$'\n\n'
block+="A Definition-of-Done barrier is in effect. The orchestrator must:"$'\n'
block+="- Run \`/dod:verify\` before declaring any non-trivial task complete."$'\n'
block+="- Treat hook block decisions as ground truth, not as suggestions."$'\n'
block+="- Refuse to bypass detector failures or skip hooks."$'\n\n'

if [[ -f "$CFG" ]]; then
    block+="### Project configuration (\`.dod-guard.json\`)"$'\n\n'
    if command -v jq >/dev/null 2>&1; then
        # Emit a compact summary: which detectors are on, strictness, runners.
        summary="$(jq -r '
            "- strictness: \(.strictness // "default")
- run_tests: \(.verification.run_tests // true)
- detectors: " + ([.detectors // {} | to_entries[] | select(.value.enabled // true) | .key] | join(", "))
        ' "$CFG" 2>/dev/null || true)"
        if [[ -n "$summary" ]]; then
            block+="$summary"$'\n\n'
        fi
    fi
fi

if [[ -f "$DOD_FILE" ]]; then
    block+="### Definition of Done (\`DOD.md\`)"$'\n\n'
    # Indent every line of DOD.md as a fenced block to preserve its structure.
    block+='```markdown'$'\n'
    block+="$(cat "$DOD_FILE")"$'\n'
    block+='```'$'\n'
fi

# Emit the JSON envelope. We use python for safe JSON encoding of the block.
python3 - "$block" <<'PYEOF'
import json, sys
ctx = sys.argv[1]
out = {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": ctx}}
sys.stdout.write(json.dumps(out))
sys.stdout.write("\n")
PYEOF
exit 0
