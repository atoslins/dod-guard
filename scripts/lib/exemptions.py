"""Shared exemption and scoping logic for the DoD-Guard Python detectors.

Reads ``.dod-guard.json`` from the current working directory and exposes:

- ``is_exempt(path)`` predicate that respects ``exemptions.paths`` globs.
- ``load_scope_roots()`` returning the ``scope.roots`` list (monorepo scoping).
- ``apply_scope(roots)`` expanding a caller-supplied ``[Path('.')]`` into the
  configured scope roots when applicable.

Supports the following glob shapes for exemptions:

- ``**/dir/**``   — any path containing ``/dir/`` or starting with ``dir/``
- ``dir/**``      — any path starting with ``dir/``
- ``*.ext``       — fnmatch shell glob
- ``literal``     — exact path or its prefix as a directory

Other patterns fall through to :func:`fnmatch.fnmatch`.
"""

from __future__ import annotations

import json
import os
from fnmatch import fnmatch
from pathlib import Path
from typing import Iterable


def _load_config(cfg_path: Path | None = None) -> dict:
    cfg = cfg_path or (Path.cwd() / ".dod-guard.json")
    if not cfg.is_file():
        return {}
    try:
        return json.loads(cfg.read_text(encoding="utf-8"))
    except Exception:
        return {}


def load_exemption_globs(cfg_path: Path | None = None) -> list[str]:
    # Allow tests to bypass exemptions entirely.
    if os.environ.get("DODG_NO_EXEMPTIONS"):
        return []
    data = _load_config(cfg_path)
    return list((data.get("exemptions") or {}).get("paths") or [])


def load_scope_roots(cfg_path: Path | None = None) -> list[str]:
    """Return ``scope.roots`` from .dod-guard.json, or [] if absent/disabled.

    The roots are returned as-written (relative paths). Set the environment
    variable ``DODG_NO_SCOPE=1`` to bypass scoping (used by tests and by
    /dod:audit's full-project mode).
    """
    if os.environ.get("DODG_NO_SCOPE"):
        return []
    data = _load_config(cfg_path)
    raw = (data.get("scope") or {}).get("roots") or []
    return [str(r) for r in raw if isinstance(r, str) and r.strip()]


def apply_scope(roots: Iterable[Path], cfg_path: Path | None = None) -> list[Path]:
    """If ``roots`` is exactly ``[Path('.')]`` and scope.roots is configured,
    replace it with the configured roots. Otherwise return ``roots`` unchanged.

    This preserves explicit callers passing specific paths (e.g. a single file
    on the CLI) while ensuring whole-project scans honor scope.
    """
    roots_list = list(roots)
    if len(roots_list) != 1:
        return roots_list
    only = roots_list[0]
    if str(only) not in (".", "./"):
        return roots_list
    scope = load_scope_roots(cfg_path)
    if not scope:
        return roots_list
    base = (cfg_path.parent if cfg_path else Path.cwd())
    return [base / r for r in scope]


def is_exempt(path: Path | str, globs: Iterable[str]) -> bool:
    s = str(path)
    if s.startswith("./"):
        s = s[2:]
    for g in globs:
        if g.startswith("**/") and g.endswith("/**"):
            inner = g[3:-3]
            if f"/{inner}/" in s or s.startswith(f"{inner}/"):
                return True
            continue
        if g.endswith("/**"):
            prefix = g[:-3]
            if s.startswith(prefix + "/") or s == prefix:
                return True
            continue
        if "*" in g or "?" in g:
            if fnmatch(s, g):
                return True
            continue
        if s == g or s.startswith(g + "/"):
            return True
    return False
