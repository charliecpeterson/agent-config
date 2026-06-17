"""Generator core: load manifest, dispatch present adapters, validate, summarize.

Partial-failure-continues: one adapter (or one validation) failing is collected,
not fatal, and surfaced in the end-of-run summary. Per-harness config dirs are
overridable via `<NAME>_DIR` env (e.g. CLAUDE_DIR) — same convention as
install.sh, which is what makes the golden test apples-to-apples.
"""
from __future__ import annotations

import argparse
import os
from collections import Counter
from datetime import datetime
from pathlib import Path

from . import manifest as manifest_mod
from . import state as state_mod
from .adapters import (
    ClaudeAdapter, CodexAdapter, CrushAdapter, OpencodeAdapter, PiAdapter,
)
from .manifest import Manifest
from .model import RunResult
from .render import RenderContext


def _state_path(env) -> Path:
    p = env.get("AGENT_CONFIG_STATE")
    return Path(p) if p else Path.home() / ".agent-config" / "state.json"


def _harness_dir(manifest: Manifest, env, name: str) -> Path:
    """Config dir for a harness, with `<NAME>_DIR` env override (matches install.sh)."""
    override = env.get(f"{name.upper()}_DIR")
    base = override or manifest.harnesses[name].config_dir
    return Path(base).expanduser()


def build_adapters(manifest: Manifest, env) -> list:
    """The adapters to consider this run (each is_present()-gated). opencode/Crush/
    pi land in later increments."""
    adapters = [ClaudeAdapter(_harness_dir(manifest, env, "claude"))]
    if "codex" in manifest.harnesses:
        adapters.append(CodexAdapter(_harness_dir(manifest, env, "codex")))
    if "opencode" in manifest.harnesses:
        adapters.append(OpencodeAdapter(_harness_dir(manifest, env, "opencode")))
    if "crush" in manifest.harnesses:
        adapters.append(CrushAdapter(_harness_dir(manifest, env, "crush")))
    if "pi" in manifest.harnesses:
        adapters.append(PiAdapter(_harness_dir(manifest, env, "pi")))
    return adapters


def run(repo_root, *, dry_run: bool = False, env=None, stamp: str | None = None) -> RunResult:
    repo_root = Path(repo_root)
    env = os.environ if env is None else env
    stamp = stamp or datetime.now().strftime("%Y%m%d-%H%M%S")

    manifest = manifest_mod.load(repo_root / "manifest.toml", repo_root)
    ctx = RenderContext(stamp, dry_run=dry_run)
    state_path = _state_path(env)
    prior = state_mod.load(state_path)

    for adapter in build_adapters(manifest, env):
        if not adapter.is_present():
            continue
        start = len(ctx.result.artifacts)
        try:
            adapter.emit(manifest, repo_root, ctx)
        except Exception as e:  # noqa: BLE001 — partial-failure-continues
            ctx.record_failure(adapter.HARNESS, e)
            continue
        if not dry_run:
            for art in ctx.result.artifacts[start:]:
                try:
                    adapter.validate(art)
                except Exception as e:  # noqa: BLE001
                    ctx.record_failure(f"{adapter.HARNESS}:validate", e)

    ctx.result.stale = state_mod.stale_paths(prior, ctx.result.artifacts)
    state_mod.save(state_path, ctx.result.artifacts, dry_run=dry_run)
    return ctx.result


def print_summary(result: RunResult, *, dry_run: bool) -> None:
    counts = Counter(verb for verb, _ in result.actions)
    ordered = [f"{counts[v]} {v}" for v in ("new", "copy", "backup", "ok") if counts[v]]
    prefix = "would " if dry_run else ""
    print(f"  {prefix}{', '.join(ordered) if ordered else 'nothing to do'}")
    for asset, err in result.failures:
        print(f"  FAIL {asset}: {err}")
    if result.stale:
        print("  stale (no longer in source — remove manually):")
        for p in result.stale:
            print(f"    {p}")


def _default_repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="agentconfig", description="render agent config")
    ap.add_argument("--check", action="store_true", help="dry-run: show changes, write nothing")
    ap.add_argument("--repo-root", default=None, help="source repo (default: this repo)")
    args = ap.parse_args(argv)

    repo_root = Path(args.repo_root) if args.repo_root else _default_repo_root()
    result = run(repo_root, dry_run=args.check)
    print_summary(result, dry_run=args.check)
    return 1 if result.failures else 0
