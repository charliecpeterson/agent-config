"""Crush adapter (charmbracelet/crush).

Verified (2026-06): config at ~/.config/crush/crush.json (plain JSON); Crush
auto-loads ~/.config/crush/CRUSH.md for rules and reads ~/.agents/skills +
~/.claude/skills natively (skills handled by skills_paths — no adapter work);
MCP under `mcp` as {type:"stdio", command, args, env}; permissions are a coarse
`allowed_tools` name list (NO command-pattern denies → deny-floor can't port).

This adapter: rules (CRUSH.md, separate file) + MCP (JSON keyed-merge). Skills
are native; permissions/subagents/hooks are gaps (see comments).
"""
from __future__ import annotations

import os
from pathlib import Path

from ..adapter import Adapter
from ..manifest import Manifest
from ..reconcile import keyed_merge_json
from ..render import RenderContext
from ..rules import render_agents_md


class CrushAdapter(Adapter):
    HARNESS = "crush"
    TESTED_AGAINST = "2026-06"

    def __init__(self, config_dir: Path) -> None:
        self.config_dir = Path(config_dir)

    def is_present(self) -> bool:
        return self.config_dir.is_dir()

    def emit(self, manifest: Manifest, repo_root, ctx: RenderContext) -> None:
        # Rules → CRUSH.md (Crush auto-loads it; separate file, no merge).
        ctx.write_file(
            self.config_dir / "CRUSH.md",
            render_agents_md(manifest, repo_root),
            harness="crush", asset="rules", source_ref="generated",
        )
        servers = {
            m.name: {
                "type": "stdio",
                "command": os.path.expanduser(m.command),
                "args": list(m.args),
            }
            for m in manifest.mcps
            if m.targets_harness("crush")
        }
        if servers:
            keyed_merge_json(
                ctx, self.config_dir / "crush.json", {"mcp": servers},
                harness="crush", asset="mcp",
            )
        # Skills: native (skills_paths → ~/.agents/skills) — nothing to do.
        # Permissions: GAP. crush.permissions.allowed_tools is a tool-name
        # allowlist with no command patterns → the bash deny-floor can't port
        # (OQ3 fail-safe). Subagents/hooks: gap (Claude-only-skill infra /
        # Claude-script-contract).
