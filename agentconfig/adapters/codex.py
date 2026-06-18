"""Codex CLI adapter (openai/codex, rust-v0.140.0).

Verified against current docs (2026-06): Codex reads a global ~/.codex/AGENTS.md
(standard discovery, not flag-gated), registers skills via [[skills.config]]
paths in config.toml (it does NOT read ~/.agents/skills — the latent bug),
takes MCP via [mcp_servers.<id>], and hooks via [hooks.<Event>] matcher groups.

Renders rules (AGENTS.md, generator-owned, no merge) plus skills and MCP as a
single keyed managed block in config.toml. Hooks and permissions are documented
gaps — no faithful Codex mapping; see the GAP notes in emit() and SUPPORT.md.
"""
from __future__ import annotations

import os
from pathlib import Path

from ..adapter import Adapter
from ..manifest import Manifest
from ..reconcile import apply_managed_block
from ..render import RenderContext
from ..rules import render_agents_md
from ..tomlfmt import mcp_servers_block, skills_config_block


class CodexAdapter(Adapter):
    HARNESS = "codex"
    TESTED_AGAINST = "rust-v0.140.0"

    def __init__(self, config_dir: Path) -> None:
        self.config_dir = Path(config_dir)

    def is_present(self) -> bool:
        return self.config_dir.is_dir()

    def emit(self, manifest: Manifest, repo_root, ctx: RenderContext) -> None:
        self._emit_rules(manifest, repo_root, ctx)
        # All config.toml content goes in ONE managed block (skills + MCP), so the
        # markers bound a single region and re-runs replace it cleanly.
        blocks: list[str] = []
        skill_paths = self._copy_skills(manifest, repo_root, ctx)
        if skill_paths:
            blocks.append(skills_config_block(skill_paths))
        servers = self._mcp_servers(manifest)
        if servers:
            blocks.append(mcp_servers_block(servers))
        if blocks:
            apply_managed_block(
                ctx, self.config_dir / "config.toml",
                "\n\n".join(blocks),
                harness="codex", asset="config",
            )
        # Hooks: GAP. The Claude hook scripts are bound to Claude's hook I/O
        # contract (.tool_input.* in, hookSpecificOutput out); run by Codex they
        # silently no-op. Registering them would be a false safety signal (D3).
        #
        # Permissions: GAP (verified 2026-06, user-confirmed). Codex has no
        # bash-command deny mechanism, so the force-push/rm-rf floor can't port.
        # File-read denies exist only inside a [permissions.<name>] profile that
        # activates via the global `default_permissions` key (mutually exclusive
        # with sandbox_mode) — emitting it would commandeer Codex's whole
        # security policy for an incomplete floor. Codex's native sandbox +
        # approval_policy is the baseline instead (OQ3 fail-safe).

    def _emit_rules(self, manifest: Manifest, repo_root, ctx: RenderContext) -> None:
        ctx.write_file(
            self.config_dir / "AGENTS.md",
            render_agents_md(manifest, repo_root),
            harness="codex", asset="rules", source_ref="generated",
        )

    def _copy_skills(self, manifest: Manifest, repo_root, ctx: RenderContext) -> list[str]:
        """Copy portable skills into ~/.codex/skills, return their paths to
        register (Codex does NOT read ~/.agents/skills — the latent bug)."""
        repo_root = Path(repo_root)
        paths: list[str] = []
        for name in sorted(manifest.portable_skills):
            src = repo_root / "skills" / name
            if not (src / "SKILL.md").is_file():
                continue
            dest = self.config_dir / "skills" / name
            ctx.copy_path(src, dest, harness="codex", asset="skills")
            paths.append(str(dest))
        return paths

    def _mcp_servers(self, manifest: Manifest) -> list[tuple[str, str, tuple[str, ...]]]:
        """MCPs the manifest targets at Codex, as (name, command, args). The
        command points at a wrapper; secrets never enter the config (D4)."""
        out = []
        for m in manifest.mcps:
            if m.targets_harness("codex"):
                out.append((m.name, os.path.expanduser(m.command), m.args))
        return out
