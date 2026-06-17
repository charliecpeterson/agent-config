"""agent-config generator: render one neutral source into each harness's config.

Phase 1 ships the pipeline (manifest loader, reconciler, managed-state store,
adapter contract, safe-I/O context) plus the Claude adapter, proven byte-
identical to the legacy install.sh placement. Other harness adapters land in
Phase 2. See PROJECT_PLAN.md.
"""

__version__ = "0.1.0"
