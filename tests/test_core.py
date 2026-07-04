"""Core-level behaviors shared across adapters: the portable-skills export to
~/.agents/skills, junk filtering in dir copies, XDG_CONFIG_HOME handling, and
state-schema drift tolerance.
"""
import json
import os
import tempfile
import unittest
from pathlib import Path

from agentconfig import manifest as manifest_mod
from agentconfig import state as state_mod
from agentconfig.core import _harness_dir, run
from agentconfig.render import RenderContext

REPO = Path(__file__).resolve().parent.parent


def _run(base: Path):
    return run(REPO, env={
        **os.environ,
        "CLAUDE_DIR": str(base / ".claude"),
        "CODEX_DIR": str(base / ".codex-absent"),
        "OPENCODE_DIR": str(base / ".opencode-absent"),
        "CRUSH_DIR": str(base / ".crush-absent"),
        "PI_DIR": str(base / ".pi-absent"),
        "AGENT_CONFIG_STATE": str(base / "state.json"),
        "AGENTS_SKILLS_DIR": str(base / "agents-skills"),
    })


class PortableSkillsTest(unittest.TestCase):
    def test_exactly_the_portable_list_is_exported(self):
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            _run(base)
            m = manifest_mod.load(REPO / "manifest.toml", REPO)
            exported = {p.name for p in (base / "agents-skills").iterdir()}
            self.assertEqual(exported, set(m.portable_skills))


class IgnoredJunkTest(unittest.TestCase):
    def test_junk_not_copied_and_comparison_ignores_it(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            src = td / "skill"
            (src / ".venv" / "bin").mkdir(parents=True)
            (src / ".venv" / "bin" / "python").write_text("fake")
            (src / "__pycache__").mkdir()
            (src / "SKILL.md").write_text("hello")
            dest = td / "out"
            ctx = RenderContext("S", backups_root=td / "backups")
            ctx.copy_path(src, dest, harness="t", asset="a")
            self.assertTrue((dest / "SKILL.md").is_file())
            self.assertFalse((dest / ".venv").exists())
            self.assertFalse((dest / "__pycache__").exists())
            # Second run must be a no-op even though src still holds the junk.
            ctx2 = RenderContext("S2", backups_root=td / "backups")
            ctx2.copy_path(src, dest, harness="t", asset="a")
            self.assertEqual([v for v, _ in ctx2.result.actions], ["ok"])


class XdgTest(unittest.TestCase):
    def test_xdg_config_home_honored(self):
        m = manifest_mod.load(REPO / "manifest.toml", REPO)
        d = _harness_dir(m, {"XDG_CONFIG_HOME": "/xdg"}, "opencode")
        self.assertEqual(d, Path("/xdg/opencode"))

    def test_env_override_beats_xdg(self):
        m = manifest_mod.load(REPO / "manifest.toml", REPO)
        d = _harness_dir(
            m, {"XDG_CONFIG_HOME": "/xdg", "OPENCODE_DIR": "/explicit"}, "opencode"
        )
        self.assertEqual(d, Path("/explicit"))


class StateDriftTest(unittest.TestCase):
    def test_unknown_field_starts_fresh_not_crash(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "state.json"
            p.write_text(json.dumps({"artifacts": [
                {"harness": "claude", "asset": "rules", "path": "/x", "kind": "file",
                 "source_ref": "", "owned_keys": [], "added_in_future": 1}
            ]}))
            self.assertEqual(state_mod.load(p), [])


if __name__ == "__main__":
    unittest.main()
