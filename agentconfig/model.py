"""Shared records passed between the generator core, adapters, and state store."""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class ManagedArtifact:
    """One placed thing the generator owns, recorded in the state store.

    `owned_keys` is for keyed-merge targets (Phase 2); files/dirs leave it empty.
    """
    harness: str
    asset: str          # rules | skills | subagents | hooks | settings | ...
    path: str           # absolute target path
    kind: str           # file | dir | merged
    source_ref: str = ""
    owned_keys: tuple[str, ...] = ()


@dataclass
class RunResult:
    """What a generator run did, for the end-of-run summary and the state diff."""
    artifacts: list[ManagedArtifact] = field(default_factory=list)
    actions: list[tuple[str, str]] = field(default_factory=list)   # (verb, path)
    failures: list[tuple[str, str]] = field(default_factory=list)  # (asset, error)
    stale: list[str] = field(default_factory=list)                 # paths no longer produced
