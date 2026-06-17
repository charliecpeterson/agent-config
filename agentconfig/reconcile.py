"""Reconciliation strategies for shared config files (D5).

`apply_managed_block` is the comment-preserving strategy for TOML configs the
user (and the harness itself) hand-edit — e.g. Codex's config.toml, which Codex
co-manages (trust levels, model migrations). We never parse-and-rewrite the
whole file; we own only the region between two markers, appended at the end,
and leave everything else byte-for-byte. Re-runs replace just that region.

JSON harness configs (opencode/Crush) use keyed-merge instead (plain JSON has no
comments to lose) — that lands with those adapters.
"""
from __future__ import annotations

import re
from pathlib import Path

from .render import RenderContext

BEGIN = "# >>> agent-config managed (regenerated each run; edits between markers are overwritten) >>>"
END = "# <<< agent-config managed <<<"
_BLOCK_RE = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n?", re.DOTALL)


def apply_managed_block(
    ctx: RenderContext, config_path, block_body: str, *, harness: str, asset: str
) -> None:
    config_path = Path(config_path)
    existing = ""
    if config_path.is_file() and not config_path.is_symlink():
        existing = config_path.read_text()

    block = f"{BEGIN}\n{block_body.rstrip()}\n{END}\n"
    if _BLOCK_RE.search(existing):
        new = _BLOCK_RE.sub(lambda _m: block, existing)  # func repl: no backslash escapes
    elif existing.strip():
        new = existing.rstrip("\n") + "\n\n" + block
    else:
        new = block

    ctx.write_file(
        config_path, new, harness=harness, asset=asset,
        kind="merged", source_ref="managed-block", owned_keys=("managed-block",),
    )
