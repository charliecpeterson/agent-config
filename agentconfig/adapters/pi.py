"""pi adapter (@mariozechner/pi-coding-agent, pi.dev).

Verified live (2026-06, pi installed at ~/.pi/agent): pi reads a GLOBAL
~/.pi/agent/AGENTS.md at startup (so rules DO port — correcting install.sh's
"pi is skills-only" assumption). pi ships WITHOUT native MCP ("No MCP";
extension-only) → MCP is a gap. Its config (settings.json/trust.json/auth.json)
is pi-managed; we touch only AGENTS.md.

The lightest adapter: rules only. Everything else is gap/native/uncertain.
"""
from __future__ import annotations

from pathlib import Path

from ..adapter import Adapter
from ..manifest import Manifest
from ..render import RenderContext
from ..rules import render_agents_md


class PiAdapter(Adapter):
    HARNESS = "pi"
    TESTED_AGAINST = "0.79.0"

    def __init__(self, config_dir: Path) -> None:
        self.config_dir = Path(config_dir)   # ~/.pi/agent

    def is_present(self) -> bool:
        return self.config_dir.is_dir()

    def emit(self, manifest: Manifest, repo_root, ctx: RenderContext) -> None:
        ctx.write_file(
            self.config_dir / "AGENTS.md",
            render_agents_md(manifest, repo_root),
            harness="pi", asset="rules", source_ref="generated",
        )
        # MCP: GAP — pi has no native MCP (extension-only).
        # Skills: pi's loader isn't confirmed to read ~/.agents/skills; left to
        # the existing export, unverified. Permissions/subagents/hooks: gap.
