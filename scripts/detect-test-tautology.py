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


def is_test_path(path: Path) -> bool:
    name = path.name
    if name.startswith("test_") and name.endswith(".py"):
        return True
    if name.endswith("_test.py") or name.endswith(".test.ts") or name.endswith(".test.tsx") \
            or name.endswith(".test.js") or name.endswith(".test.jsx") \
            or name.endswith(".spec.ts") or name.endswith(".spec.js"):
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
            if p.suffix not in JS_EXTS and p.suffix not in PY_EXTS:
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
        files = [p for p in changed if p.exists() and (p.suffix in PY_EXTS or p.suffix in JS_EXTS) and is_test_path(p)]
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
