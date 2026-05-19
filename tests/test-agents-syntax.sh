#!/usr/bin/env bash
# tests/test-agents-syntax.sh
# Validate the YAML frontmatter of every agent and command file, and assert
# each one carries the structural pieces DoD-Guard relies on.

set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)"
cd "$ROOT" || exit 2

GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'
PASSED=0
FAILED=0

assert() {
    local name="$1" actual="$2" op="$3" expected="$4"
    local ok=0
    case "$op" in
        ==) [[ "$actual" == "$expected" ]] && ok=1 ;;
        contains) [[ "$actual" == *"$expected"* ]] && ok=1 ;;
    esac
    if [[ "$ok" -eq 1 ]]; then
        PASSED=$((PASSED + 1))
        echo "  ${GREEN}PASS${RESET}  $name"
    else
        FAILED=$((FAILED + 1))
        echo "  ${RED}FAIL${RESET}  $name"
        echo "        actual:   '$actual'"
        echo "        expected: contains '$expected'"
    fi
}

validate_frontmatter() {
    local file="$1"
    python3 - "$file" <<'PYEOF'
import sys, re
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
if not m:
    print("ERR: no frontmatter")
    sys.exit(1)
fm = m.group(1)
# Crude key:value parser — good enough for plain mappings.
keys = {}
for line in fm.splitlines():
    line = line.rstrip()
    if not line or line.startswith("#"):
        continue
    if ":" in line and not line.startswith(" "):
        k, v = line.split(":", 1)
        keys[k.strip()] = v.strip()
required = ["name", "description"]
missing = [k for k in required if k not in keys]
if missing:
    print("ERR: missing keys:", ",".join(missing))
    sys.exit(2)
print(f"OK name={keys['name']} desc_len={len(keys['description'])}")
PYEOF
}

echo "== agents/*.md frontmatter validation =="
for f in agents/*.md; do
    res="$(validate_frontmatter "$f" 2>&1)"
    rc=$?
    if [[ "$rc" -eq 0 ]]; then
        PASSED=$((PASSED + 1))
        echo "  ${GREEN}PASS${RESET}  $f → $res"
    else
        FAILED=$((FAILED + 1))
        echo "  ${RED}FAIL${RESET}  $f → $res"
    fi
done

echo ""
echo "== agents must list 'Failure modes' and require commands_run =="
for f in agents/*.md; do
    body_lc="$(tr '[:upper:]' '[:lower:]' < "$f")"
    body="$(cat "$f")"
    assert "$f has 'failure modes' section"          "$body_lc" contains "failure modes"
    assert "$f mandates commands_run"                "$body" contains "commands_run"
    assert "$f forbids file modification"            "$body" contains "disallowedTools"
done

echo ""
echo "== commands/*.md frontmatter validation =="
if compgen -G "commands/*.md" > /dev/null; then
    for f in commands/*.md; do
        res="$(validate_frontmatter "$f" 2>&1)"
        rc=$?
        if [[ "$rc" -eq 0 ]]; then
            PASSED=$((PASSED + 1))
            echo "  ${GREEN}PASS${RESET}  $f → $res"
        else
            FAILED=$((FAILED + 1))
            echo "  ${RED}FAIL${RESET}  $f → $res"
        fi
    done
else
    echo "  (no commands yet — skipped)"
fi

echo ""
echo "------------------------------------------------------------"
echo "  ${PASSED} passed, ${FAILED} failed"
echo "------------------------------------------------------------"
[[ "$FAILED" -gt 0 ]] && exit 1
exit 0
