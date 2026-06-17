"""Claude Code adapter — the reference harness.

Reproduces the legacy install.sh placement into ~/.claude, byte-identical (the
Phase-1 golden-test bar): the four rule files, settings.json, every skill,
every sub-agent, and the hooks dir are copied; CLAUDE.md is *generated* from the
manifest preamble + one @import per rule file (honoring D1 — Claude is just an
adapter that renders, not a privileged source).
"""
from __future__ import annotations

from pathlib import Path

from ..adapter import Adapter
from ..manifest import Manifest
from ..render import RenderContext


class ClaudeAdapter(Adapter):
    HARNESS = "claude"
    TESTED_AGAINST = "2026-06"

    def __init__(self, config_dir: Path) -> None:
        self.config_dir = Path(config_dir)

    def is_present(self) -> bool:
        # Claude is the always-rendered reference; skip-absent is for the others.
        return True

    def emit(self, manifest: Manifest, repo_root, ctx: RenderContext) -> None:
        repo_root = Path(repo_root)
        self._emit_rules(manifest, repo_root, ctx)
        self._emit_settings(repo_root, ctx)
        self._emit_skills(repo_root, ctx)
        self._emit_subagents(repo_root, ctx)
        self._emit_hooks(repo_root, ctx)

    # ---- per-asset emitters ------------------------------------------------

    def _emit_rules(self, manifest: Manifest, repo_root: Path, ctx: RenderContext) -> None:
        for name in manifest.rule_files:
            ctx.copy_path(
                repo_root / name, self.config_dir / name,
                harness="claude", asset="rules",
            )
        preamble = manifest.claude_preamble.rstrip("\n")
        imports = "".join(f"@./{name}\n" for name in manifest.rule_files)
        ctx.write_file(
            self.config_dir / "CLAUDE.md", f"{preamble}\n\n{imports}",
            harness="claude", asset="rules", source_ref="generated",
        )

    def _emit_settings(self, repo_root: Path, ctx: RenderContext) -> None:
        src = repo_root / "settings.json"
        if src.is_file():
            ctx.copy_path(src, self.config_dir / "settings.json",
                          harness="claude", asset="settings")

    def _emit_skills(self, repo_root: Path, ctx: RenderContext) -> None:
        skills = repo_root / "skills"
        if not skills.is_dir():
            return
        for d in sorted(skills.iterdir()):
            if d.is_dir() and (d / "SKILL.md").is_file():
                ctx.copy_path(d, self.config_dir / "skills" / d.name,
                              harness="claude", asset="skills")

    def _emit_subagents(self, repo_root: Path, ctx: RenderContext) -> None:
        agents = repo_root / "agents"
        if not agents.is_dir():
            return
        for f in sorted(agents.glob("*.md")):
            ctx.copy_path(f, self.config_dir / "agents" / f.name,
                          harness="claude", asset="subagents")

    def _emit_hooks(self, repo_root: Path, ctx: RenderContext) -> None:
        hooks = repo_root / "hooks"
        if hooks.is_dir():
            ctx.copy_path(hooks, self.config_dir / "hooks",
                          harness="claude", asset="hooks")
