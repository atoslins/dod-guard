#!/usr/bin/env python3
"""Detect functions with trivial bodies.

Python files are parsed with :mod:`ast` for accuracy. Other supported languages
use language-aware regex heuristics. Output is JSON compatible with the rest of
the DoD-Guard detector family::

    {"count": int, "issues": [...], "summary": str}

Each issue has the shape ``{file, line, type, evidence, severity}``.

Usage::

    detect-empty-functions.py <file-or-dir> [<file-or-dir> ...] [--json|--text]
"""

from __future__ import annotations

import argparse
import ast
import json
import os
import re
import sys
from pathlib import Path
from typing import Iterable, List

# Make scripts/lib importable when the script is invoked directly.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
from exemptions import apply_scope, is_exempt, load_exemption_globs  # noqa: E402

PY_TRIVIAL_TOKENS = {"Pass", "Ellipsis", "Constant_None"}

# Directories we never scan into.
SKIP_DIRS = {
    "node_modules", ".git", "__pycache__", ".venv", "venv",
    "target", "dist", "build", ".dod-guard", ".pytest_cache",
    ".mypy_cache", ".ruff_cache",
}

SOURCE_EXTS = {
    ".py": "python",
    ".js": "node", ".cjs": "node", ".mjs": "node", ".jsx": "node",
    ".ts": "typescript", ".tsx": "typescript",
    ".go": "go",
    ".rs": "rust",
    ".rb": "ruby",
    ".java": "java",
    ".kt": "kotlin", ".kts": "kotlin",
}


def iter_files(roots: Iterable[Path]) -> Iterable[Path]:
    globs = load_exemption_globs()
    for root in apply_scope(roots):
        if root.is_file():
            if root.suffix in SOURCE_EXTS and not is_exempt(root, globs):
                yield root
            continue
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            if any(part in SKIP_DIRS for part in path.parts):
                continue
            if path.suffix not in SOURCE_EXTS:
                continue
            if is_exempt(path, globs):
                continue
            yield path


def _python_body_is_trivial(body: list[ast.stmt]) -> tuple[bool, str]:
    """Return (trivial?, evidence-tag) for a Python function body."""
    # Drop a leading docstring — a stub with only a docstring is still a stub.
    real = body
    if real and isinstance(real[0], ast.Expr) and isinstance(real[0].value, ast.Constant) \
            and isinstance(real[0].value.value, str):
        real = real[1:]

    if not real:
        return True, "docstring-only"

    if len(real) == 1:
        stmt = real[0]
        if isinstance(stmt, ast.Pass):
            return True, "pass"
        if isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Constant) \
                and stmt.value.value is Ellipsis:
            return True, "..."
        if isinstance(stmt, ast.Return):
            if stmt.value is None:
                return True, "return"
            if isinstance(stmt.value, ast.Constant) and stmt.value.value is None:
                return True, "return None"
        if isinstance(stmt, ast.Raise) and isinstance(stmt.exc, ast.Call) \
                and isinstance(stmt.exc.func, ast.Name) \
                and stmt.exc.func.id == "NotImplementedError":
            return True, "raise NotImplementedError"

    return False, ""


def scan_python(path: Path) -> List[dict]:
    try:
        src = path.read_text(encoding="utf-8", errors="replace")
        tree = ast.parse(src, filename=str(path))
    except (SyntaxError, OSError):
        return []

    issues: List[dict] = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        # Skip @abstractmethod / @typing.overload — they are *meant* to be empty.
        if _has_decorator(node, {"abstractmethod", "overload", "abc.abstractmethod"}):
            continue
        trivial, tag = _python_body_is_trivial(node.body)
        if trivial:
            issues.append({
                "file": str(path),
                "line": node.lineno,
                "type": "empty_function",
                "evidence": f"def {node.name}(...) -> {tag}",
                "severity": "high",
            })
    return issues


def _has_decorator(node: ast.AST, names: set[str]) -> bool:
    decorators = getattr(node, "decorator_list", []) or []
    for dec in decorators:
        if isinstance(dec, ast.Name) and dec.id in names:
            return True
        if isinstance(dec, ast.Attribute):
            full = _attr_full_name(dec)
            if full in names:
                return True
        if isinstance(dec, ast.Call):
            if isinstance(dec.func, ast.Name) and dec.func.id in names:
                return True
            if isinstance(dec.func, ast.Attribute):
                full = _attr_full_name(dec.func)
                if full in names:
                    return True
    return False


def _attr_full_name(node: ast.Attribute) -> str:
    parts: list[str] = [node.attr]
    cur = node.value
    while isinstance(cur, ast.Attribute):
        parts.append(cur.attr)
        cur = cur.value
    if isinstance(cur, ast.Name):
        parts.append(cur.id)
    return ".".join(reversed(parts))


JS_FUNC_RE = re.compile(
    r"""
    (?P<head>
        \b(?:function|async\s+function)\s+(?P<name>[A-Za-z_$][\w$]*)\s*\([^)]*\)\s*\{ |
        \b(?:async\s+)?(?P<name2>[A-Za-z_$][\w$]*)\s*\([^)]*\)\s*\{ |
        \b(?:const|let|var)\s+(?P<name3>[A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?\([^)]*\)\s*=>\s*\{
    )
    \s*\}
    """,
    re.VERBOSE,
)

GO_FUNC_RE = re.compile(
    r"\bfunc\s+(?:\([^)]*\)\s*)?(?P<name>[A-Za-z_]\w*)\s*\([^)]*\)\s*(?:[^{]*?)\{\s*\}",
)

RUST_FUNC_RE = re.compile(
    r"\bfn\s+(?P<name>[A-Za-z_]\w*)\s*(?:<[^>]*>)?\s*\([^)]*\)\s*(?:->\s*[^{]+?)?\{\s*\}",
)

RUBY_FUNC_RE = re.compile(
    r"\bdef\s+(?P<name>[A-Za-z_]\w*[!?=]?)\s*(?:\([^)]*\))?\s*\n\s*end\b",
)


def _line_of(src: str, offset: int) -> int:
    return src.count("\n", 0, offset) + 1


def scan_with_regex(path: Path, kind: str, pattern: re.Pattern) -> List[dict]:
    try:
        src = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    issues = []
    for m in pattern.finditer(src):
        name = m.group("name") if "name" in m.groupdict() and m.group("name") else "?"
        issues.append({
            "file": str(path),
            "line": _line_of(src, m.start()),
            "type": "empty_function",
            "evidence": f"{kind} {name}() {{}}",
            "severity": "high",
        })
    return issues


def scan(path: Path) -> List[dict]:
    lang = SOURCE_EXTS.get(path.suffix, "unknown")
    if lang == "python":
        return scan_python(path)
    if lang in {"node", "typescript"}:
        return scan_with_regex(path, "function", JS_FUNC_RE)
    if lang == "go":
        return scan_with_regex(path, "func", GO_FUNC_RE)
    if lang == "rust":
        return scan_with_regex(path, "fn", RUST_FUNC_RE)
    if lang == "ruby":
        return scan_with_regex(path, "def", RUBY_FUNC_RE)
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("targets", nargs="+")
    parser.add_argument("--json", action="store_const", const="json", dest="fmt", default="json")
    parser.add_argument("--text", action="store_const", const="text", dest="fmt")
    args = parser.parse_args()

    roots = [Path(t) for t in args.targets]
    issues: List[dict] = []
    n_files = 0
    for f in iter_files(roots):
        n_files += 1
        issues.extend(scan(f))

    if args.fmt == "text":
        print(f"Scanned {n_files} file(s) — {len(issues)} empty-function issue(s).")
        for i in issues:
            print(f"  HIGH  {i['file']}:{i['line']}  [{i['type']}]  {i['evidence']}")
    else:
        json.dump(
            {
                "count": len(issues),
                "issues": issues,
                "summary": f"Scanned {n_files} file(s)",
            },
            sys.stdout,
            indent=None,
        )
        sys.stdout.write("\n")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
