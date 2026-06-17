"""Parse Claude settings.json permissions into a neutral (tool, pattern) form.

settings.json's allow/deny lists ARE the permission source of truth; each
adapter translates them into its harness's native model. This module does the
parsing once; the per-harness mapping (e.g. Claude `Bash(cmd:*)` -> opencode
command glob) lives in each adapter, since the models differ.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

_RULE = re.compile(r"^(\w+)\((.*)\)$")


def load_claude_perms(settings_path) -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    """Return (allow, deny), each a list of (tool, pattern) — e.g.
    ("Bash", "git status:*") or ("Read", "~/.ssh/id_*")."""
    data = json.loads(Path(settings_path).read_text())
    perms = data.get("permissions", {})
    return _parse(perms.get("allow", [])), _parse(perms.get("deny", []))


def _parse(rules: list[str]) -> list[tuple[str, str]]:
    out = []
    for s in rules:
        m = _RULE.match(s)
        if m:
            out.append((m.group(1), m.group(2)))
    return out
