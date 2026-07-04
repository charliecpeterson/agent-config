"""Resolve which machine profile applies to this host and render the
"Machines" section every harness's rules carry: which box this session is on
(specs, role, scheduler) plus the rest of the fleet, so agents can route work
to the machine that fits. Profiles are body-only markdown under machines/;
headings come from here.
"""
from __future__ import annotations

import socket
from fnmatch import fnmatch
from pathlib import Path

from .manifest import Manifest


def _profile(repo_root: Path, name: str) -> str:
    return (repo_root / "machines" / f"{name}.md").read_text().strip()


def _current(manifest: Manifest, repo_root: Path, env) -> tuple[str, str, str]:
    """(display name, profile body, how-it-was-resolved note) for this host.

    Fallback order for an unmatched hostname: ~/.agent-config/machine.local.md
    (hand-written, never synced — the settings.local.json idiom), then
    machines/other.md.
    """
    host = env.get("AGENT_CONFIG_HOSTNAME") or socket.gethostname()
    for m in manifest.machines:
        if any(fnmatch(host.lower(), pat.lower()) for pat in m.hosts):
            return m.name, _profile(repo_root, m.name), f"host `{host}`"
    local = Path(
        env.get("AGENT_CONFIG_MACHINE_LOCAL") or "~/.agent-config/machine.local.md"
    ).expanduser()
    if local.is_file():
        return ("this machine (local profile)", local.read_text().strip(),
                f"host `{host}`, machine-local profile")
    return ("an unrecognized machine", _profile(repo_root, "other"),
            f"host `{host}`, not in the fleet map")


def machines_section(manifest: Manifest, repo_root, env) -> str:
    """The rendered "## Machines" block, or "" when the manifest declares no
    machines (feature off)."""
    if not manifest.machines:
        return ""
    repo_root = Path(repo_root)
    name, body, note = _current(manifest, repo_root, env)
    parts = [
        "## Machines",
        "",
        f"You are on: **{name}** ({note}).",
        "",
        f"### {name} — this machine",
        "",
        body,
    ]
    fleet = [m for m in manifest.machines if m.name != name]
    if fleet:
        parts += ["", "Also available — route work to whichever machine fits the task:"]
        for m in fleet:
            parts += ["", f"### {m.name}", "", _profile(repo_root, m.name)]
    return "\n".join(parts) + "\n"
