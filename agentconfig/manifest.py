"""Load and validate manifest.toml into typed, frozen dataclasses.

Read-only: tomllib parses, we never write TOML back. Validation is fail-fast —
a structural problem (missing rule file, unknown skill, missing claude harness)
raises before the generator touches a single target file.
"""
from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path


class ManifestError(ValueError):
    """A manifest that is malformed or references things that don't exist."""


@dataclass(frozen=True)
class Harness:
    name: str
    config_dir: Path
    strategy: str


@dataclass(frozen=True)
class Mcp:
    name: str
    command: str
    args: tuple[str, ...]
    targets: frozenset[str]   # harness names, or "*" for all

    def targets_harness(self, harness: str) -> bool:
        return "*" in self.targets or harness in self.targets


@dataclass(frozen=True)
class Manifest:
    repo_name: str
    rule_files: tuple[str, ...]
    claude_preamble: str
    portable_skills: frozenset[str]
    harnesses: dict[str, Harness]
    mcps: tuple[Mcp, ...]


def load(manifest_path: str | Path, repo_root: str | Path) -> Manifest:
    repo_root = Path(repo_root)
    raw = Path(manifest_path).read_bytes()
    try:
        data = tomllib.loads(raw.decode("utf-8"))
    except tomllib.TOMLDecodeError as e:
        raise ManifestError(f"manifest.toml is not valid TOML: {e}") from e

    repo_name = _req(data, "meta", "repo_name")

    rules = _req_table(data, "rules")
    rule_files = tuple(rules.get("files", []))
    if not rule_files:
        raise ManifestError("[rules].files is empty")
    for f in rule_files:
        if not (repo_root / f).is_file():
            raise ManifestError(f"[rules].files references missing file: {f}")
    preamble = rules.get("claude_preamble", "")
    if not preamble.strip():
        raise ManifestError("[rules].claude_preamble is empty")

    portable = frozenset(data.get("skills", {}).get("portable", []))
    skills_dir = repo_root / "skills"
    for s in portable:
        if not (skills_dir / s / "SKILL.md").is_file():
            raise ManifestError(
                f"[skills].portable names a skill with no skills/{s}/SKILL.md"
            )

    harnesses: dict[str, Harness] = {}
    for name, h in data.get("harness", {}).items():
        cfg = h.get("config_dir")
        if not cfg:
            raise ManifestError(f"[harness.{name}] missing config_dir")
        harnesses[name] = Harness(
            name=name,
            config_dir=Path(cfg).expanduser(),
            strategy=h.get("strategy", "separate-file"),
        )
    if "claude" not in harnesses:
        raise ManifestError("[harness.claude] is required")

    mcps = []
    for name, m in data.get("mcp", {}).items():
        cmd = m.get("command")
        if not cmd:
            raise ManifestError(f"[mcp.{name}] missing command")
        mcps.append(Mcp(
            name=name,
            command=cmd,
            args=tuple(m.get("args", [])),
            targets=frozenset(m.get("targets", ["*"])),
        ))

    return Manifest(
        repo_name=repo_name,
        rule_files=rule_files,
        claude_preamble=preamble,
        portable_skills=portable,
        harnesses=harnesses,
        mcps=tuple(mcps),
    )


def _req(data: dict, table: str, key: str):
    val = data.get(table, {}).get(key)
    if val is None:
        raise ManifestError(f"[{table}].{key} is required")
    return val


def _req_table(data: dict, table: str) -> dict:
    val = data.get(table)
    if not isinstance(val, dict):
        raise ManifestError(f"[{table}] table is required")
    return val
