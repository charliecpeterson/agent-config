"""Adapter registry. Explicit dict (not autoload) — greppable, right for a
fixed small set. A 6th harness is one import + one entry here (Phase 2)."""
from .claude import ClaudeAdapter

__all__ = ["ClaudeAdapter"]
