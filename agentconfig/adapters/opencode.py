"""opencode adapter (sst/opencode).

Verified (2026-06): config at ~/.config/opencode/opencode.json (plain JSON or
JSONC); opencode reads ~/.agents/skills natively (so skills need NO adapter
work — the export already covers it); MCP under the `mcp` key as
{type:"local", command:[...], enabled}; permissions are command-pattern
allow/ask/deny (the "closest to Claude" model — ported in the next increment).

This increment: rules (AGENTS.md, separate file) + MCP (JSON keyed-merge into
opencode.json). Subagents (agent/subagents/), commands, and permissions follow.
"""
from __future__ import annotations

import os
from pathlib import Path

from ..adapter import Adapter
from ..manifest import Manifest
from ..permissions import load_claude_perms
from ..reconcile import keyed_merge_json
from ..render import RenderContext
from ..rules import render_agents_md


class OpencodeAdapter(Adapter):
    HARNESS = "opencode"
    TESTED_AGAINST = "2026-06"

    def __init__(self, config_dir: Path) -> None:
        self.config_dir = Path(config_dir)

    def is_present(self) -> bool:
        return self.config_dir.is_dir()

    def emit(self, manifest: Manifest, repo_root, ctx: RenderContext) -> None:
        ctx.write_file(
            self.config_dir / "AGENTS.md",
            render_agents_md(manifest, repo_root),
            harness="opencode", asset="rules", source_ref="generated",
        )
        servers = {
            m.name: {
                "type": "local",
                "command": [os.path.expanduser(m.command), *m.args],
                "enabled": True,
            }
            for m in manifest.mcps
            if m.targets_harness("opencode")
        }
        if servers:
            keyed_merge_json(
                ctx, self.config_dir / "opencode.json", {"mcp": servers},
                harness="opencode", asset="mcp",
            )
        self._emit_permissions(repo_root, ctx)
        # Skills: native (~/.agents/skills) — nothing to do.

    def _emit_permissions(self, repo_root, ctx: RenderContext) -> None:
        """Port the bash allow/deny floor to opencode's command-pattern model
        (the 'closest to Claude' permission model — denies port faithfully).
        Read() credential denies are a gap: opencode governs bash/edit, not
        file reads."""
        settings = Path(repo_root) / "settings.json"
        if not settings.is_file():
            return
        allow, deny = load_claude_perms(settings)
        bash = {"*": "ask"}  # Claude's implicit default
        for tool, pat in allow:
            if tool == "Bash":
                bash[self._glob(pat)] = "allow"
        for tool, pat in deny:           # denies last → last-match-wins → they win
            if tool == "Bash":
                bash[self._glob(pat)] = "deny"
        keyed_merge_json(
            ctx, self.config_dir / "opencode.json", {"permission": {"bash": bash}},
            harness="opencode", asset="permissions",
        )

    @staticmethod
    def _glob(pattern: str) -> str:
        """Claude `cmd:*` (cmd + args) -> opencode `cmd*` glob; exact stays exact."""
        return pattern[:-2] + "*" if pattern.endswith(":*") else pattern
