"""Minimal TOML emit for the *specific* structures the generator owns.

Deliberately NOT a general TOML serializer — we never round-trip a user's
arbitrary config (that would drop comments and reorder their content). We only
format our own known shapes (skills.config entries, and later mcp_servers/hooks)
as text, dropped into a managed block by reconcile.py.
"""
from __future__ import annotations


def toml_str(s: str) -> str:
    """A TOML basic string with minimal escaping (paths, names)."""
    esc = s.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{esc}"'


def skills_config_block(paths: list[str]) -> str:
    """`[[skills.config]]` array-of-tables registering each skill folder."""
    out: list[str] = []
    for p in paths:
        out += ["[[skills.config]]", f"path = {toml_str(p)}", "enabled = true", ""]
    return "\n".join(out).rstrip()
