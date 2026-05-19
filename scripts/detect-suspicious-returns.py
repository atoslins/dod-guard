#!/usr/bin/env python3
"""Detect suspicious returns of empty values from action-flavored functions.

The premise: a function named ``create_user`` that returns ``None`` (or ``{}``,
or ``[]``) under all branches is almost certainly a stub. The detector flags
*single-statement* returns of empty values inside functions whose name uses an
action verb (create, update, delete, fetch, get, build, make, save, send,
publish, run, execute, parse, encode, decode, hash, sign, verify, validate,
authenticate, authorize, login, logout, register, schedule, enqueue, process).

Output JSON: ``{count, issues, summary}``.

Usage::

    detect-suspicious-returns.py <file-or-dir> [<file-or-dir> ...] [--json|--text]
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

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
from exemptions import load_exemption_globs, is_exempt  # noqa: E402

SKIP_DIRS = {
    "node_modules", ".git", "__pycache__", ".venv", "venv",
    "target", "dist", "build", ".dod-guard",
}

SOURCE_EXTS = {
    ".py": "python",
    ".js": "node", ".cjs": "node", ".mjs": "node", ".jsx": "node",
    ".ts": "typescript", ".tsx": "typescript",
    ".go": "go",
}

ACTION_VERBS = {
    "create", "update", "delete", "remove", "fetch", "get", "load",
    "build", "make", "save", "store", "send", "publish", "post",
    "run", "execute", "exec", "perform", "do",
    "parse", "encode", "decode", "hash", "sign", "verify", "validate",
    "authenticate", "authorize", "login", "logout", "register",
    "schedule", "enqueue", "dispatch", "process", "handle",
    "compute", "calculate", "generate", "produce", "render",
    "upload", "download", "import", "export", "sync",
}


def looks_like_action(name: str) -> bool:
    norm = re.sub(r"[^A-Za-z]", " ", name).lower().strip().split()
    if not norm:
        return False
    return norm[0] in ACTION_VERBS or any(v in norm for v in ACTION_VERBS)


def iter_files(roots: Iterable[Path]) -> Iterable[Path]:
    globs = load_exemption_globs()
    for root in roots:
        if root.is_file():
            if root.suffix in SOURCE_EXTS and not is_exempt(root, globs):
                yield root
            continue
        if not root.exists():
            continue
        for p in root.rglob("*"):
            if not p.is_file():
                continue
            if any(part in SKIP_DIRS for part in p.parts):
                continue
            if p.suffix not in SOURCE_EXTS:
                continue
            if is_exempt(p, globs):
                continue
            yield p


def _python_returns_empty(body: list[ast.stmt]) -> str | None:
    """If every return in *body* returns an empty literal, return a tag."""
    returns = [n for n in ast.walk(ast.Module(body=body, type_ignores=[])) if isinstance(n, ast.Return)]
    if not returns:
        return None
    seen = set()
    for r in returns:
        if r.value is None:
            seen.add("None")
        elif isinstance(r.value, ast.Constant) and r.value.value is None:
            seen.add("None")
        elif isinstance(r.value, ast.Dict) and not r.value.keys:
            seen.add("{}")
        elif isinstance(r.value, ast.List) and not r.value.elts:
            seen.add("[]")
        elif isinstance(r.value, ast.Tuple) and not r.value.elts:
            seen.add("()")
        elif isinstance(r.value, ast.Constant) and r.value.value in ("", 0, False):
            seen.add(repr(r.value.value))
        else:
            return None
    return ",".join(sorted(seen))


def scan_python(path: Path) -> List[dict]:
    try:
        tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"), filename=str(path))
    except (SyntaxError, OSError):
        return []
    issues = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        if not looks_like_action(node.name):
            continue
        tag = _python_returns_empty(node.body)
        if tag:
            issues.append({
                "file": str(path),
                "line": node.lineno,
                "type": "suspicious_return",
                "evidence": f"{node.name}(...) only returns {tag}",
                "severity": "high",
            })
    return issues


JS_FUNC_RE = re.compile(
    r"""
    (?:
      \b(?:function|async\s+function)\s+(?P<name>[A-Za-z_$][\w$]*)\s*\([^)]*\)\s*\{ |
      \b(?:const|let|var)\s+(?P<name2>[A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?\([^)]*\)\s*=>\s*\{
    )
    (?P<body>(?:[^{}]|\{[^{}]*\})*)
    \}
    """,
    re.VERBOSE,
)

JS_RETURN_EMPTY = re.compile(r"return\s*(?:null|undefined|\{\s*\}|\[\s*\]|''|\"\")\s*;?\s*$", re.MULTILINE)
JS_ANY_OTHER_RETURN = re.compile(r"return\s+(?!null\b|undefined\b|\{\s*\}|\[\s*\]|''|\"\"|;|\s*$)")


def scan_js(path: Path) -> List[dict]:
    try:
        src = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    issues = []
    for m in JS_FUNC_RE.finditer(src):
        name = m.group("name") or m.group("name2") or ""
        if not name or not looks_like_action(name):
            continue
        body = m.group("body")
        empties = JS_RETURN_EMPTY.findall(body)
        if not empties:
            continue
        if JS_ANY_OTHER_RETURN.search(body):
            continue
        line = src.count("\n", 0, m.start()) + 1
        issues.append({
            "file": str(path),
            "line": line,
            "type": "suspicious_return",
            "evidence": f"{name}() only returns empty value(s)",
            "severity": "high",
        })
    return issues


GO_FUNC_RE = re.compile(
    r"""
    \bfunc\s+(?:\([^)]*\)\s*)?(?P<name>[A-Za-z_]\w*)\s*\([^)]*\)\s*(?:[^{]*?)\{
    (?P<body>(?:[^{}]|\{[^{}]*\})*)
    \}
    """,
    re.VERBOSE,
)

GO_RETURN_EMPTY = re.compile(r"return\s+(?:nil|0|\"\"|false)(?:\s*,\s*(?:nil|0|\"\"|false))*\s*$", re.MULTILINE)
GO_ANY_RETURN = re.compile(r"return\b")

# Constructor: `func NewX(...) *X { return &X{} }` or `func NewX(...) X { return X{} }`
# where the body's only statement is the return of a zero-valued struct.
GO_CONSTRUCTOR_RE = re.compile(
    r"""
    \bfunc\s+(?P<name>New[A-Z]\w*)\s*\([^)]*\)\s*
    (?:\*?)(?P<rtype>[A-Z]\w*)\s*\{
    (?P<body>(?:[^{}]|\{[^{}]*\})*)
    \}
    """,
    re.VERBOSE,
)
GO_RETURN_ZERO_STRUCT = re.compile(
    r"return\s+&?(?P<rtype>[A-Z]\w*)\s*\{\s*\}\s*$",
    re.MULTILINE,
)

# Error-swallow patterns. We flag the discarded `err` assignment (`_ = err`,
# `_, _ = ..., err`) — that erases the error before anything can react to it.
GO_ERROR_SWALLOW_RES = [
    (re.compile(r"^\s*_\s*=\s*err\b", re.MULTILINE),
     "_ = err — error discarded"),
    (re.compile(r"^\s*_\s*,\s*_\s*=", re.MULTILINE),
     "_, _ = ... — return values, including error, discarded"),
]


def scan_go(path: Path) -> List[dict]:
    try:
        src = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    issues = []

    # 1. Action-named functions that always return zero values.
    for m in GO_FUNC_RE.finditer(src):
        name = m.group("name") or ""
        if not looks_like_action(name):
            continue
        body = m.group("body")
        returns = GO_ANY_RETURN.findall(body)
        empties = GO_RETURN_EMPTY.findall(body)
        if returns and empties and len(returns) == len(empties):
            line = src.count("\n", 0, m.start()) + 1
            issues.append({
                "file": str(path),
                "line": line,
                "type": "suspicious_return",
                "evidence": f"{name}() only returns zero values",
                "severity": "high",
            })

    # 2. NewX constructors that return a zero-valued struct with no field set.
    for m in GO_CONSTRUCTOR_RE.finditer(src):
        name = m.group("name")
        rtype = m.group("rtype")
        body = m.group("body").strip()
        # If every statement in the body is the zero-struct return, flag it.
        body_lines = [ln.strip() for ln in body.splitlines() if ln.strip()]
        only_return_zero = (
            len(body_lines) == 1
            and GO_RETURN_ZERO_STRUCT.search(body_lines[0]) is not None
        )
        if only_return_zero:
            line = src.count("\n", 0, m.start()) + 1
            issues.append({
                "file": str(path),
                "line": line,
                "type": "uninitialized_constructor",
                "evidence": f"{name}() returns &{rtype}{{}} / {rtype}{{}} with no fields set",
                "severity": "high",
            })

    # 3. Error-swallow patterns anywhere in the file.
    for lineno, raw in enumerate(src.splitlines(), start=1):
        for pat, tag in GO_ERROR_SWALLOW_RES:
            if pat.search(raw):
                issues.append({
                    "file": str(path),
                    "line": lineno,
                    "type": "error_swallow",
                    "evidence": raw.strip(),
                    "severity": "high",
                })
                break

    return issues


def scan(path: Path) -> List[dict]:
    lang = SOURCE_EXTS.get(path.suffix, "unknown")
    if lang == "python":
        return scan_python(path)
    if lang in {"node", "typescript"}:
        return scan_js(path)
    if lang == "go":
        return scan_go(path)
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("targets", nargs="+")
    parser.add_argument("--json", action="store_const", const="json", dest="fmt", default="json")
    parser.add_argument("--text", action="store_const", const="text", dest="fmt")
    args = parser.parse_args()

    issues: List[dict] = []
    n = 0
    for f in iter_files(Path(t) for t in args.targets):
        n += 1
        issues.extend(scan(f))

    if args.fmt == "text":
        print(f"Scanned {n} file(s) — {len(issues)} suspicious-return issue(s).")
        for i in issues:
            print(f"  HIGH  {i['file']}:{i['line']}  [{i['type']}]  {i['evidence']}")
    else:
        json.dump({"count": len(issues), "issues": issues, "summary": f"Scanned {n} file(s)"}, sys.stdout)
        sys.stdout.write("\n")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
