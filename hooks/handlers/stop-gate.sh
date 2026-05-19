#!/usr/bin/env bash
# hooks/handlers/stop-gate.sh
# Stop hook: refuses to let the orchestrator end its turn while the DoD is
# unmet. This is the *last* barrier — without it the other layers can be
# bypassed by simply declaring "done."
#
# Loop prevention is critical. The Claude Code Stop hook payload carries
# `stop_hook_active: true` when the agent is already mid-stop-cycle; in that
# state we MUST exit 0 so the user is not trapped.
#
# Input JSON (stdin): { "stop_hook_active": bool, "transcript_path": "...", ... }

set -uo pipefail

PLUGIN_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/../.. && pwd)"
SCRIPT_DIR="$PLUGIN_ROOT/scripts"

payload="$(cat || true)"

# 1. Bail when DoD-Guard is not configured.
if [[ ! -f ".dod-guard.json" ]]; then
    exit 0
fi

# 2. Loop prevention — release the agent if we're already in an active stop.
stop_active="false"
if command -v jq >/dev/null 2>&1; then
    stop_active="$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
fi
if [[ "$stop_active" == "true" ]]; then
    exit 0
fi

# 3. Skip when there were no mutations this session — nothing to verify.
transcript_path=""
if command -v jq >/dev/null 2>&1; then
    transcript_path="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
fi
had_mutation=1
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    if grep -qE '"(Write|Edit|MultiEdit|NotebookEdit)"' "$transcript_path" 2>/dev/null; then
        had_mutation=1
    else
        had_mutation=0
    fi
fi
if [[ "$had_mutation" -eq 0 ]]; then
    exit 0
fi

# 4. Run the verification pipeline. We allow skipping tests via config to keep
#    Stop fast; the agent should run /dod:verify with full tests on its own.
skip_tests_flag=""
if command -v jq >/dev/null 2>&1; then
    st="$(jq -r '.hooks.stop_gate.skip_tests // false' .dod-guard.json 2>/dev/null || echo false)"
    [[ "$st" == "true" ]] && skip_tests_flag="--skip-tests"
fi

result_json="$(bash "$SCRIPT_DIR/run-verification-pipeline.sh" $skip_tests_flag --json 2>/dev/null || true)"
verdict="FAIL"
if command -v jq >/dev/null 2>&1; then
    verdict="$(printf '%s' "$result_json" | jq -r '.verdict // "FAIL"' 2>/dev/null || echo FAIL)"
fi

if [[ "$verdict" == "PASS" ]]; then
    mkdir -p .dod-guard
    date +%s > .dod-guard/last-verify-passed
    exit 0
fi

# 5. Build the instructional reason: tell the agent what to do.
mkdir -p .dod-guard/reports
if [[ -n "$result_json" ]]; then
    printf '%s\n' "$result_json" > .dod-guard/reports/last-stop-gate.json
fi

reason="DoD-Guard: cannot end the turn — Definition of Done is unmet."$'\n'
if command -v jq >/dev/null 2>&1; then
    summary="$(printf '%s' "$result_json" | jq -r '.reasons | join(", ")' 2>/dev/null || true)"
    [[ -n "$summary" ]] && reason+="Reasons: $summary"$'\n'
fi
reason+="Next steps:"$'\n'
reason+="  1. Run /dod:verify to see the full list of blocking issues."$'\n'
reason+="  2. Fix each issue with real implementation (no stubs, no skips)."$'\n'
reason+="  3. Re-run /dod:verify until it passes."$'\n'
reason+="  4. Then attempt to end your turn again."$'\n'

python3 - "$reason" <<'PYEOF'
import json, sys
print(json.dumps({"decision": "block", "reason": sys.argv[1]}))
PYEOF
exit 0
