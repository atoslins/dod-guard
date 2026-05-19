"""Shared exemption logic for the DoD-Guard Python detectors.

Reads ``.dod-guard.json`` from the current working directory and exposes a
``is_exempt(path)`` predicate that respects ``exemptions.paths`` globs.

Supports the following glob shapes:

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


def load_exemption_globs(cfg_path: Path | None = None) -> list[str]:
    # Allow tests to bypass exemptions entirely.
    if os.environ.get("DODG_NO_EXEMPTIONS"):
        return []
    cfg = cfg_path or (Path.cwd() / ".dod-guard.json")
    if not cfg.is_file():
        return []
    try:
        data = json.loads(cfg.read_text(encoding="utf-8"))
    except Exception:
        return []
    return list((data.get("exemptions") or {}).get("paths") or [])


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
