#!/usr/bin/env bash
# hooks/handlers/subagent-stop.sh
# SubagentStop hook: record every subagent's final output to disk so that
# /dod:report and the final-judge agent can read a tamper-evident audit trail.
#
# Does NOT block. Pure observer.

set -uo pipefail

payload="$(cat || true)"

# No project opt-in → exit silently.
if [[ ! -f ".dod-guard.json" ]]; then
    exit 0
fi

session_id="unknown-session"
agent_name="unknown-agent"
if command -v jq >/dev/null 2>&1; then
    session_id="$(printf '%s' "$payload" | jq -r '.session_id // "unknown-session"' 2>/dev/null || echo unknown-session)"
    agent_name="$(printf '%s' "$payload" | jq -r '.agent_name // .subagent_name // .tool_input.agent // "unknown-agent"' 2>/dev/null || echo unknown-agent)"
fi

# Sanitize for use as a filename.
agent_name="${agent_name//[^A-Za-z0-9_.-]/_}"
session_id="${session_id//[^A-Za-z0-9_.-]/_}"

dir=".dod-guard/reports/$session_id"
mkdir -p "$dir"

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
file="$dir/${agent_name}.json"

# Append (not overwrite) — a single subagent may emit multiple stops in a session.
if [[ -f "$file" ]]; then
    file="$dir/${agent_name}-${timestamp//[:T]/-}.json"
fi

# Wrap the raw payload in an envelope so downstream consumers always know the
# timestamp and the agent identity.
python3 - "$timestamp" "$agent_name" "$session_id" "$payload" "$file" <<'PYEOF'
import json, sys, pathlib
timestamp, agent, session, raw, dest = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
try:
    body = json.loads(raw) if raw.strip() else {}
except Exception:
    body = {"_raw": raw}
envelope = {
    "session_id": session,
    "agent_name": agent,
    "timestamp": timestamp,
    "payload": body,
}
pathlib.Path(dest).write_text(json.dumps(envelope, indent=2))
PYEOF
exit 0
