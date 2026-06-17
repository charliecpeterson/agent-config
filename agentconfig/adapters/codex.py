"""Codex CLI adapter (openai/codex, rust-v0.140.0).

Verified against current docs (2026-06): Codex reads a global ~/.codex/AGENTS.md
(standard discovery, not flag-gated), registers skills via [[skills.config]]
paths in config.toml (it does NOT read ~/.agents/skills — the latent bug),
takes MCP via [mcp_servers.<id>], and hooks via [hooks.<Event>] matcher groups.

This increment renders rules (AGENTS.md — a generator-owned file, no merge). The
config.toml asset types (skills/MCP/hooks/permissions) land with the keyed-merge
reconciler + TOML writer in the next increment.
"""
from __future__ import annotations

from pathlib import Path

from ..adapter import Adapter
from ..manifest import Manifest
from ..render import RenderContext
from ..rules import render_agents_md


class CodexAdapter(Adapter):
    HARNESS = "codex"
    TESTED_AGAINST = "rust-v0.140.0"

    def __init__(self, config_dir: Path) -> None:
        self.config_dir = Path(config_dir)

    def is_present(self) -> bool:
        return self.config_dir.is_dir()

    def emit(self, manifest: Manifest, repo_root, ctx: RenderContext) -> None:
        ctx.write_file(
            self.config_dir / "AGENTS.md",
            render_agents_md(manifest, repo_root),
            harness="codex", asset="rules", source_ref="generated",
        )
