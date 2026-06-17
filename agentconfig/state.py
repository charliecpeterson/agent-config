"""Managed-state store: ~/.agent-config/state.json (machine-local).

Records exactly which artifacts the generator owns, per run. On the next run it
answers one question Phase 1 uses — "what did I place last time that's no longer
in source?" — to produce the stale report. It is never an authority to delete
(D7): the report names stale paths; removal is manual. Regenerable; losing it
costs only stale-report continuity.

Phase 2 also uses `owned_keys` here for keyed-merge safety.
"""
from __future__ import annotations

import dataclasses
import json
import os
from pathlib import Path

from .model import ManagedArtifact


def load(path) -> list[ManagedArtifact]:
    path = Path(path)
    if not path.is_file():
        return []
    try:
        data = json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return []  # corrupt/unreadable state is non-fatal — start fresh
    out = []
    for d in data.get("artifacts", []):
        d = {**d, "owned_keys": tuple(d.get("owned_keys", ()))}
        out.append(ManagedArtifact(**d))
    return out


def save(path, artifacts: list[ManagedArtifact], *, dry_run: bool = False) -> None:
    if dry_run:
        return
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"artifacts": [dataclasses.asdict(a) for a in artifacts]}
    tmp = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    tmp.write_text(json.dumps(payload, indent=2))
    os.replace(tmp, path)


def stale_paths(prior: list[ManagedArtifact], current: list[ManagedArtifact]) -> list[str]:
    """Paths owned last run but not produced this run (report-only; never deleted)."""
    now = {a.path for a in current}
    return [a.path for a in prior if a.path not in now]
