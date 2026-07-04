"""Machines feature: hostname-to-profile resolution, the fallback chain
(fleet match, then machine.local.md, then other.md), and the rendered section
landing in CLAUDE.md imports and AGENTS.md.
"""
import os
import tempfile
import unittest
from pathlib import Path

from agentconfig import machines as machines_mod
from agentconfig import manifest as manifest_mod
from agentconfig.core import run

REPO = Path(__file__).resolve().parent.parent
MANIFEST = manifest_mod.load(REPO / "manifest.toml", REPO)


def _env(base: Path, **extra):
    return {
        **os.environ,
        "CLAUDE_DIR": str(base / ".claude"),
        "CODEX_DIR": str(base / ".codex-absent"),
        "OPENCODE_DIR": str(base / ".opencode-absent"),
        "CRUSH_DIR": str(base / ".crush-absent"),
        "PI_DIR": str(base / ".pi-absent"),
        "AGENT_CONFIG_STATE": str(base / "state.json"),
        "AGENTS_SKILLS_DIR": str(base / "agents-skills"),
        # points at a nonexistent file unless a test writes it
        "AGENT_CONFIG_MACHINE_LOCAL": str(base / "machine.local.md"),
        **extra,
    }


class ResolutionTest(unittest.TestCase):
    def test_matched_host_renders_profile_plus_fleet(self):
        s = machines_mod.machines_section(MANIFEST, REPO, {
            "AGENT_CONFIG_HOSTNAME": "login2.stampede3.tacc.utexas.edu",
            "AGENT_CONFIG_MACHINE_LOCAL": "/nonexistent",
        })
        self.assertIn("You are on: **stampede3**", s)
        self.assertIn("### mac-studio", s)                    # fleet listed
        self.assertEqual(s.count("### stampede3"), 1)         # not repeated in fleet

    def test_unmatched_host_uses_machine_local_when_present(self):
        with tempfile.TemporaryDirectory() as td:
            local = Path(td) / "machine.local.md"
            local.write_text("- borrowed conference laptop, 8 GB RAM\n")
            s = machines_mod.machines_section(MANIFEST, REPO, {
                "AGENT_CONFIG_HOSTNAME": "randombox",
                "AGENT_CONFIG_MACHINE_LOCAL": str(local),
            })
            self.assertIn("borrowed conference laptop", s)
            self.assertIn("machine-local profile", s)
            self.assertIn("### stampede3", s)                 # fleet still listed

    def test_unmatched_host_falls_back_to_other(self):
        s = machines_mod.machines_section(MANIFEST, REPO, {
            "AGENT_CONFIG_HOSTNAME": "randombox",
            "AGENT_CONFIG_MACHINE_LOCAL": "/nonexistent",
        })
        self.assertIn("unrecognized machine", s)
        self.assertIn("not in the fleet map", s)


class RenderIntegrationTest(unittest.TestCase):
    def test_claude_gets_machines_md_and_import(self):
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            run(REPO, env=_env(base, AGENT_CONFIG_HOSTNAME="charlie-m2studio.local"))
            cd = base / ".claude"
            self.assertIn("@./machines.md", (cd / "CLAUDE.md").read_text())
            self.assertIn("You are on: **mac-studio**", (cd / "machines.md").read_text())

    def test_agents_md_carries_the_section(self):
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            oc = base / "opencode"
            oc.mkdir()
            run(REPO, env=_env(base, OPENCODE_DIR=str(oc),
                               AGENT_CONFIG_HOSTNAME="charlie-m2studio.local"))
            text = (oc / "AGENTS.md").read_text()
            self.assertIn("## Machines", text)
            self.assertIn("You are on: **mac-studio**", text)


if __name__ == "__main__":
    unittest.main()
