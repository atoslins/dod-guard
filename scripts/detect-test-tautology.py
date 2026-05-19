#!/usr/bin/env python3
"""Detect decorative or tautological tests.

Patterns flagged:

* Jest/Vitest: ``expect(x).toBeDefined()``, ``.not.toBeNull()``,
  ``.toBeTruthy()`` on a literal-truthy value, ``.toEqual(...)`` where both
  sides are the same expression.
* Pytest: ``assert x`` where ``x`` is a literal-truthy constant; ``assert x is
  not None`` as the only assertion in a test body.
* Skipped tests added in the current git diff (``test.skip``, ``xit``,
  ``@pytest.mark.skip``, ``@unittest.skip``).

Output JSON: ``{count, issues, summary}``.

Usage::

    detect-test-tautology.py <file-or-dir> [...] [--diff] [--json|--text]

When ``--diff`` is passed, the scope is restricted to files (and added lines)
of the current git diff.
"""

from __future__ import annotations

import argparse
import ast
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Iterable, List

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
from exemptions import load_exemption_globs, is_exempt  # noqa: E402

SKIP_DIRS = {
    "node_modules", ".git", "__pycache__", ".venv", "venv",
    "target", "dist", "build", ".dod-guard",
}

JS_EXTS = {".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx"}
PY_EXTS = {".py"}
GO_EXTS = {".go"}


def is_test_path(path: Path) -> bool:
    name = path.name
    if name.startswith("test_") and name.endswith(".py"):
        return True
    if name.endswith("_test.py") or name.endswith(".test.ts") or name.endswith(".test.tsx") \
            or name.endswith(".test.js") or name.endswith(".test.jsx") \
            or name.endswith(".spec.ts") or name.endswith(".spec.js"):
        return True
    if name.endswith("_test.go"):
        return True
    parts = set(path.parts)
    return bool(parts & {"tests", "test", "__tests__", "spec"})


def iter_files(roots: Iterable[Path]) -> Iterable[Path]:
    globs = load_exemption_globs()
    for root in roots:
        if root.is_file():
            if not is_exempt(root, globs):
                yield root
            continue
        if not root.exists():
            continue
        for p in root.rglob("*"):
            if not p.is_file():
                continue
            if any(part in SKIP_DIRS for part in p.parts):
                continue
            if p.suffix not in JS_EXTS and p.suffix not in PY_EXTS and p.suffix not in GO_EXTS:
                continue
            if not is_test_path(p):
                continue
            if is_exempt(p, globs):
                continue
            yield p


JS_TRIVIAL_ASSERTS = [
    (re.compile(r"expect\([^)]*\)\.toBeDefined\(\)"), "expect(...).toBeDefined()"),
    (re.compile(r"expect\([^)]*\)\.not\.toBeNull\(\)"), "expect(...).not.toBeNull()"),
    (re.compile(r"expect\([^)]*\)\.not\.toBeUndefined\(\)"), "expect(...).not.toBeUndefined()"),
    (re.compile(r"expect\(\s*(true|1|\"[^\"]+\"|'[^']+')\s*\)\.toBeTruthy\(\)"), "expect(<literal>).toBeTruthy()"),
    (re.compile(r"expect\(\s*(true|1|\"[^\"]+\"|'[^']+')\s*\)\.toBe\(\s*\1\s*\)"), "expect(x).toBe(x)"),
    # `expect(mock).toHaveBeenCalled()` with no `.toHaveBeenCalledWith(...)` next to it.
    # We catch the lone form; a chained .toHaveBeenCalledWith on the same line is fine.
    (re.compile(r"expect\([^)]*\)\.toHaveBeenCalled\(\)\s*;?\s*$"), "expect(mock).toHaveBeenCalled() — no args asserted"),
    # `expect.assertions(0)` disables the assertion-count safety net entirely.
    (re.compile(r"\bexpect\.assertions\(\s*0\s*\)"), "expect.assertions(0) — disables count check"),
    # Trivial snapshots: snapshotting an empty literal proves nothing.
    (re.compile(r"expect\(\s*(?:\{\s*\}|\[\s*\]|''|\"\"|null|undefined)\s*\)\.toMatchSnapshot\("), "expect(<empty>).toMatchSnapshot()"),
    # Node's built-in assert with literal truthy.
    (re.compile(r"\bassert(?:\.ok)?\(\s*(?:true|1|\"[^\"]+\"|'[^']+')\s*[,\)]"), "assert(<literal>) — Node assert with literal"),
    # chai/should: `expect(x).to.be.ok` and `.to.exist` are weak.
    (re.compile(r"\.to\.(?:be\.ok|exist)\s*;?\s*$"), ".to.be.ok / .to.exist (chai) — weak assertion"),
]

JS_TAUTOLOGY_TOEQUAL = re.compile(r"expect\(\s*([^)]+?)\s*\)\.toEqual\(\s*([^)]+?)\s*\)")
JS_SKIP_PATTERNS = [
    (re.compile(r"\b(?:test|it|describe)\.skip\b"), "test.skip"),
    (re.compile(r"\bxit\s*\("), "xit("),
    (re.compile(r"\bxdescribe\s*\("), "xdescribe("),
    (re.compile(r"@SkipTest"), "@SkipTest"),
]


def scan_js(path: Path) -> List[dict]:
    try:
        src = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    issues = []
    lines = src.splitlines()
    for lineno, line in enumerate(lines, start=1):
        for pat, tag in JS_TRIVIAL_ASSERTS:
            if pat.search(line):
                issues.append({
                    "file": str(path), "line": lineno, "type": "test_tautology",
                    "evidence": line.strip(), "severity": "high",
                })
                break
        m = JS_TAUTOLOGY_TOEQUAL.search(line)
        if m and m.group(1).strip() == m.group(2).strip():
            issues.append({
                "file": str(path), "line": lineno, "type": "test_tautology",
                "evidence": f"expect({m.group(1).strip()}).toEqual({m.group(2).strip()})",
                "severity": "high",
            })
        for pat, tag in JS_SKIP_PATTERNS:
            if pat.search(line):
                issues.append({
                    "file": str(path), "line": lineno, "type": "test_skipped",
                    "evidence": line.strip(), "severity": "warn",
                })
                break
    return issues


def _py_assert_is_trivial(stmt: ast.Assert) -> str | None:
    test = stmt.test
    # `assert True`, `assert 1`, `assert "non-empty"`
    if isinstance(test, ast.Constant) and bool(test.value):
        return f"assert {test.value!r}"
    # `assert x is not None` (alone in the test)
    if isinstance(test, ast.Compare) and len(test.ops) == 1 \
            and isinstance(test.ops[0], ast.IsNot) \
            and len(test.comparators) == 1 \
            and isinstance(test.comparators[0], ast.Constant) \
            and test.comparators[0].value is None:
        return "assert <x> is not None"
    return None


def _py_skip_decorator(node: ast.AST) -> str | None:
    for dec in getattr(node, "decorator_list", []) or []:
        rep = None
        if isinstance(dec, ast.Attribute):
            rep = _attr_full_name(dec)
        elif isinstance(dec, ast.Call):
            if isinstance(dec.func, ast.Attribute):
                rep = _attr_full_name(dec.func)
            elif isinstance(dec.func, ast.Name):
                rep = dec.func.id
        elif isinstance(dec, ast.Name):
            rep = dec.id
        if rep and ("skip" in rep.lower()):
            return rep
    return None


def _attr_full_name(node: ast.Attribute) -> str:
    parts = [node.attr]
    cur = node.value
    while isinstance(cur, ast.Attribute):
        parts.append(cur.attr)
        cur = cur.value
    if isinstance(cur, ast.Name):
        parts.append(cur.id)
    return ".".join(reversed(parts))


def scan_python(path: Path) -> List[dict]:
    try:
        src = path.read_text(encoding="utf-8", errors="replace")
        tree = ast.parse(src, filename=str(path))
    except (SyntaxError, OSError):
        return []
    issues = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            if not node.name.startswith("test"):
                continue
            skip = _py_skip_decorator(node)
            if skip:
                issues.append({
                    "file": str(path), "line": node.lineno, "type": "test_skipped",
                    "evidence": f"@{skip}", "severity": "warn",
                })
            # Flag if the body consists solely of trivial asserts.
            real = [s for s in node.body if not (isinstance(s, ast.Expr) and isinstance(s.value, ast.Constant)
                                                  and isinstance(s.value.value, str))]
            if real and all(isinstance(s, ast.Assert) and _py_assert_is_trivial(s) for s in real):
                first = real[0]
                tag = _py_assert_is_trivial(first) or "trivial"
                issues.append({
                    "file": str(path), "line": first.lineno, "type": "test_tautology",
                    "evidence": tag, "severity": "high",
                })
    return issues


# ─────────────────────────── Go ───────────────────────────

GO_TEST_FUNC_RE = re.compile(
    r"^func\s+(Test\w+)\s*\(\s*t\s+\*testing\.T\s*\)\s*\{",
    re.MULTILINE,
)

# Tautological / decorative Go-test patterns.
GO_TRIVIAL_PATTERNS = [
    (re.compile(r"\bassert\.(?:True|Truef)\(\s*t\s*,\s*true\b"),
     "assert.True(t, true) — tautology"),
    (re.compile(r"\bassert\.(?:Equal|Equalf)\(\s*t\s*,\s*([^,]+?)\s*,\s*\1\s*[,\)]"),
     "assert.Equal(t, x, x) — tautology"),
    (re.compile(r"\bassert\.NotNil\(\s*t\s*,\s*&\w+\{\s*\}\s*\)"),
     "assert.NotNil(t, &X{}) — comparing against literal non-nil"),
    (re.compile(r"\b(?:require|assert)\.NoError\(\s*t\s*,\s*nil\s*\)"),
     "assert.NoError(t, nil) — tautology"),
]

# `t.Skip(...)` / `t.SkipNow()` (warn).
GO_SKIP_RE = re.compile(r"\bt\.(?:Skip|Skipf|SkipNow)\s*\(")
# `t.Log("TODO")` style markers.
GO_TODO_LOG_RE = re.compile(r"\bt\.(?:Log|Logf)\s*\(\s*[\"`][^\"`]*(?:TODO|FIXME|XXX)[^\"`]*[\"`]")


def _go_test_body_has_assertion(body: str) -> bool:
    """Return True if the body contains anything that resembles a real assertion."""
    # Conservative: look for any t.* call other than t.Helper/t.Cleanup/t.Skip/t.Log,
    # or use of common assertion packages.
    significant = re.compile(
        r"\bt\.(?:Errorf?|Fatalf?|FailNow|Fail|Helper)\b|"
        r"\b(?:assert|require)\.\w+\("
    )
    return bool(significant.search(body))


def scan_go(path: Path) -> List[dict]:
    try:
        src = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    issues: List[dict] = []
    lines = src.splitlines()

    # Line-level patterns (tautologies, skips, t.Log TODO).
    for lineno, line in enumerate(lines, start=1):
        for pat, tag in GO_TRIVIAL_PATTERNS:
            if pat.search(line):
                issues.append({
                    "file": str(path), "line": lineno, "type": "test_tautology",
                    "evidence": line.strip(), "severity": "high",
                })
                break
        if GO_SKIP_RE.search(line):
            issues.append({
                "file": str(path), "line": lineno, "type": "test_skipped",
                "evidence": line.strip(), "severity": "warn",
            })
        if GO_TODO_LOG_RE.search(line):
            issues.append({
                "file": str(path), "line": lineno, "type": "test_todo_log",
                "evidence": line.strip(), "severity": "warn",
            })

    # Body-level: a TestX function whose body has no real assertion.
    # We extract the body by brace-matching from the opening { after the signature.
    for m in GO_TEST_FUNC_RE.finditer(src):
        fname = m.group(1)
        start = m.end() - 1  # position of the opening brace
        depth = 0
        end = start
        for i, ch in enumerate(src[start:], start=start):
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        body = src[start + 1:end]
        # Empty body is caught by detect-empty-functions; skip here.
        if not body.strip():
            continue
        if not _go_test_body_has_assertion(body):
            line = src.count("\n", 0, m.start()) + 1
            issues.append({
                "file": str(path), "line": line, "type": "test_no_assertion",
                "evidence": f"func {fname}(t *testing.T) — body has no assertion-like call",
                "severity": "high",
            })

    return issues


def diff_files() -> set[Path]:
    try:
        out = subprocess.run(
            ["git", "diff", "--name-only", "--diff-filter=AM"],
            capture_output=True, text=True, check=False,
        )
        cached = subprocess.run(
            ["git", "diff", "--name-only", "--cached", "--diff-filter=AM"],
            capture_output=True, text=True, check=False,
        )
        names = (out.stdout + "\n" + cached.stdout).splitlines()
        return {Path(n.strip()) for n in names if n.strip()}
    except FileNotFoundError:
        return set()


def scan(path: Path) -> List[dict]:
    if path.suffix in PY_EXTS:
        return scan_python(path)
    if path.suffix in JS_EXTS:
        return scan_js(path)
    if path.suffix in GO_EXTS:
        return scan_go(path)
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("targets", nargs="*", default=["."])
    parser.add_argument("--diff", action="store_true",
                        help="restrict scan to files changed in the current git diff")
    parser.add_argument("--json", action="store_const", const="json", dest="fmt", default="json")
    parser.add_argument("--text", action="store_const", const="text", dest="fmt")
    args = parser.parse_args()

    if args.diff:
        changed = diff_files()
        files = [
            p for p in changed
            if p.exists()
            and (p.suffix in PY_EXTS or p.suffix in JS_EXTS or p.suffix in GO_EXTS)
            and is_test_path(p)
        ]
    else:
        files = list(iter_files(Path(t) for t in args.targets))

    issues: List[dict] = []
    for f in files:
        issues.extend(scan(f))

    if args.fmt == "text":
        print(f"Scanned {len(files)} test file(s) — {len(issues)} issue(s).")
        for i in issues:
            sev = i["severity"].upper()
            print(f"  {sev}  {i['file']}:{i['line']}  [{i['type']}]  {i['evidence']}")
    else:
        json.dump({"count": len(issues), "issues": issues, "summary": f"Scanned {len(files)} test file(s)"}, sys.stdout)
        sys.stdout.write("\n")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
