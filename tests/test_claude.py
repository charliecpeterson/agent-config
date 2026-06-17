"""Durable tests for the Claude adapter + RenderContext.

The one-time "byte-identical to legacy install.sh" golden gate passed before the
cut-over (see git history). These tests give the same assurance going forward:
the legacy bash just copied source files, so "generator output equals the source"
is equivalent — plus idempotency and the safe-I/O guarantees. Everything renders
into temp dirs; the real ~/.claude is never touched.
"""
import filecmp
import os
import tempfile
import unittest
from pathlib import Path

from agentconfig import manifest as manifest_mod
from agentconfig.core import run
from agentconfig.render import RenderContext

REPO = Path(__file__).resolve().parent.parent


def _render(claude_dir):
    return run(REPO, env={**os.environ, "CLAUDE_DIR": str(claude_dir)})


class ClaudeRenderTest(unittest.TestCase):
    def test_generated_claude_md_matches_repo(self):
        with tempfile.TemporaryDirectory() as td:
            cd = Path(td) / ".claude"
            _render(cd)
            self.assertEqual(
                (cd / "CLAUDE.md").read_text(), (REPO / "CLAUDE.md").read_text()
            )

    def test_every_source_asset_placed_and_equal(self):
        with tempfile.TemporaryDirectory() as td:
            cd = Path(td) / ".claude"
            _render(cd)
            m = manifest_mod.load(REPO / "manifest.toml", REPO)
            for f in (*m.rule_files, "settings.json"):
                self.assertTrue(filecmp.cmp(REPO / f, cd / f, shallow=False), f)
            for skill in (REPO / "skills").iterdir():
                if (skill / "SKILL.md").is_file():
                    self.assertTrue(
                        filecmp.cmp(
                            skill / "SKILL.md",
                            cd / "skills" / skill.name / "SKILL.md",
                            shallow=False,
                        ),
                        skill.name,
                    )
            for agent in (REPO / "agents").glob("*.md"):
                self.assertTrue(
                    filecmp.cmp(agent, cd / "agents" / agent.name, shallow=False),
                    agent.name,
                )
            self.assertTrue((cd / "hooks" / "statusline.sh").is_file())

    def test_idempotent_second_run_is_noop(self):
        with tempfile.TemporaryDirectory() as td:
            cd = Path(td) / ".claude"
            _render(cd)
            res = _render(cd)
            self.assertEqual({v for v, _ in res.actions}, {"ok"}, res.actions)
            self.assertEqual(res.failures, [])


class RenderContextTest(unittest.TestCase):
    def test_backup_on_change_skip_on_unchanged(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            dest = td / "f.txt"
            ctx = RenderContext("STAMP")
            ctx.write_file(dest, "v1", harness="t", asset="a")
            self.assertEqual(dest.read_text(), "v1")

            ctx.write_file(dest, "v1", harness="t", asset="a")  # unchanged
            self.assertEqual(list(td.glob("*.backup-*")), [])

            ctx.write_file(dest, "v2", harness="t", asset="a")  # changed
            self.assertEqual(dest.read_text(), "v2")
            self.assertEqual((td / "f.txt.backup-STAMP").read_text(), "v1")

    def test_symlink_replaced_with_copy(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            (td / "f.txt").write_text("real")
            link = td / "link.txt"
            link.symlink_to(td / "f.txt")
            RenderContext("S").write_file(link, "fresh", harness="t", asset="a")
            self.assertFalse(link.is_symlink())
            self.assertEqual(link.read_text(), "fresh")

    def test_dry_run_writes_nothing(self):
        with tempfile.TemporaryDirectory() as td:
            dest = Path(td) / "f.txt"
            ctx = RenderContext("S", dry_run=True)
            ctx.write_file(dest, "x", harness="t", asset="a")
            self.assertFalse(dest.exists())
            self.assertEqual([v for v, _ in ctx.result.actions], ["new"])


if __name__ == "__main__":
    unittest.main()
