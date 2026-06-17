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


def mcp_servers_block(servers: list[tuple[str, str, tuple[str, ...]]]) -> str:
    """`[mcp_servers.<name>]` tables. Each tuple is (name, command, args)."""
    out: list[str] = []
    for name, command, args in servers:
        out.append(f"[mcp_servers.{name}]")
        out.append(f"command = {toml_str(command)}")
        if args:
            out.append("args = [" + ", ".join(toml_str(a) for a in args) + "]")
        out.append("")
    return "\n".join(out).rstrip()
