"""Content lint: the cross-references between skills, agents, and docs stay
true. Catches the drift review keeps finding by hand — a skill spawning an
agent that doesn't exist, a cited references/ file that was renamed, an agent
no skill invokes, SUPPORT.md's agent count going stale.
"""
import re
import unittest
from pathlib import Path

from agentconfig import manifest as manifest_mod

REPO = Path(__file__).resolve().parent.parent
SKILL_DIRS = sorted(d for d in (REPO / "skills").iterdir() if d.is_dir())
AGENT_FILES = sorted((REPO / "agents").glob("*.md"))


def _frontmatter(path: Path) -> str | None:
    m = re.match(r"---\n(.*?)\n---\n", path.read_text(), re.DOTALL)
    return m.group(1) if m else None


def _skill_docs(skill_dir: Path):
    return sorted(skill_dir.rglob("*.md"))


class SkillLint(unittest.TestCase):
    def test_frontmatter_name_matches_dir_and_description_present(self):
        for d in SKILL_DIRS:
            md = d / "SKILL.md"
            self.assertTrue(md.is_file(), f"skills/{d.name}: no SKILL.md")
            fm = _frontmatter(md)
            self.assertIsNotNone(fm, f"skills/{d.name}: no frontmatter")
            name = re.search(r"^name:\s*(\S+)\s*$", fm, re.MULTILINE)
            self.assertIsNotNone(name, f"skills/{d.name}: no name field")
            self.assertEqual(name.group(1), d.name,
                             f"skills/{d.name}: frontmatter name mismatch")
            self.assertRegex(fm, r"(?m)^description:",
                             f"skills/{d.name}: no description")

    def test_cited_reference_files_exist(self):
        for d in SKILL_DIRS:
            for md in _skill_docs(d):
                for ref in set(re.findall(r"references/[\w.-]+\.md", md.read_text())):
                    self.assertTrue(
                        (d / ref).is_file(),
                        f"skills/{d.name}/{md.name} cites missing {ref}",
                    )

    def test_spawned_agents_exist(self):
        agent_names = {a.stem for a in AGENT_FILES}
        pat = re.compile(r'subagent_type:\s*"?([\w-]+)"?')
        for d in SKILL_DIRS:
            for md in _skill_docs(d):
                for name in pat.findall(md.read_text()):
                    self.assertIn(
                        name, agent_names,
                        f"skills/{d.name}/{md.name} spawns unknown agent '{name}'",
                    )

    def test_portable_skills_spawn_no_subagents(self):
        m = manifest_mod.load(REPO / "manifest.toml", REPO)
        for name in sorted(m.portable_skills):
            for md in _skill_docs(REPO / "skills" / name):
                self.assertNotIn(
                    "subagent_type", md.read_text(),
                    f"portable skill {name} spawns sub-agents "
                    "(Claude-only machinery; drop it from [skills].portable)",
                )


class AgentLint(unittest.TestCase):
    def test_frontmatter_name_matches_filename(self):
        for a in AGENT_FILES:
            fm = _frontmatter(a)
            self.assertIsNotNone(fm, f"agents/{a.name}: no frontmatter")
            name = re.search(r"^name:\s*(\S+)\s*$", fm, re.MULTILINE)
            self.assertIsNotNone(name, f"agents/{a.name}: no name field")
            self.assertEqual(name.group(1), a.stem,
                             f"agents/{a.name}: frontmatter name mismatch")

    def test_every_agent_has_a_consumer_skill(self):
        all_skill_text = "\n".join(
            md.read_text() for d in SKILL_DIRS for md in _skill_docs(d)
        )
        for a in AGENT_FILES:
            self.assertIn(
                a.stem, all_skill_text,
                f"agents/{a.name}: no skill mentions it — orphaned worker?",
            )


class MachineLint(unittest.TestCase):
    def test_profiles_and_manifest_in_sync(self):
        # manifest.load already fails on a declared machine with no profile;
        # this catches the reverse — a profile file nothing declares.
        m = manifest_mod.load(REPO / "manifest.toml", REPO)
        declared = {x.name for x in m.machines}
        on_disk = {p.stem for p in (REPO / "machines").glob("*.md")} - {"other", "README"}
        self.assertEqual(
            on_disk, declared,
            "machines/*.md and manifest [machine.*] entries out of sync",
        )


class SupportLint(unittest.TestCase):
    def test_agent_count_current(self):
        m = re.search(r"The (\d+) agents", (REPO / "SUPPORT.md").read_text())
        self.assertIsNotNone(m, "SUPPORT.md: 'The N agents' sentence not found")
        self.assertEqual(
            int(m.group(1)), len(AGENT_FILES),
            f"SUPPORT.md says {m.group(1)} agents; agents/ has {len(AGENT_FILES)}",
        )


if __name__ == "__main__":
    unittest.main()
