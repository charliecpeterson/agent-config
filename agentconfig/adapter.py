"""The adapter contract every harness implements.

Phase 1 has one adapter (Claude). The contract is deliberately small so a 6th
harness is a new module + a manifest block + a test, with no core changes. In
Phase 2 `emit` becomes matrix-driven per-asset dispatch; for now each adapter
emits all the asset types it supports.
"""
from __future__ import annotations

from abc import ABC, abstractmethod

from .manifest import Manifest
from .model import ManagedArtifact
from .render import RenderContext


class Adapter(ABC):
    HARNESS: str = ""
    TESTED_AGAINST: str = ""

    @abstractmethod
    def is_present(self) -> bool:
        """Whether this harness should be rendered on this machine. Never raises;
        returns False if unsure (skip-absent)."""

    @abstractmethod
    def emit(self, manifest: Manifest, repo_root, ctx: RenderContext) -> None:
        """Render this harness's assets, writing through `ctx`."""

    def validate(self, artifact: ManagedArtifact) -> None:
        """Re-check one emitted artifact (parse/schema). Default: no-op."""
