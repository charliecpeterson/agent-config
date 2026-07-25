"""RenderContext: the safe-I/O primitives every adapter writes through.

No adapter opens a file directly. This is where "never clobber hand edits"
becomes a system property: writes are atomic (temp + os.replace), a changed
real file is backed up before replacement, an unchanged target is a no-op, and
a leftover symlink from the old install model is replaced with a real copy.
Honors a dry-run mode and collects partial failures so one bad asset doesn't
abort the run.
"""
from __future__ import annotations

import filecmp
import os
import shutil
from pathlib import Path

from .model import ManagedArtifact, RunResult

# Build/runtime junk that can sit inside a source dir (install.sh builds the
# security-review-deep MCP venv in-repo). Never copied into a target, and
# invisible to tree comparison — otherwise a 45 MB venv gets copied, diffed,
# and backed up on every run.
_IGNORED_NAMES = {"__pycache__", ".venv", ".ruff_cache", ".DS_Store"}


def _ignored(name: str) -> bool:
    return name in _IGNORED_NAMES or name.endswith((".egg-info", ".pyc"))


class RenderContext:
    def __init__(
        self, stamp: str, *, dry_run: bool = False, backups_root: Path | None = None
    ) -> None:
        self.stamp = stamp
        self.dry_run = dry_run
        self.result = RunResult()
        # Rendered "## Machines" block ("" = no machines declared). Core fills
        # it once per run; every adapter appends it to the rules it emits.
        self.machines_md = ""
        # Backups land under a central tree, NOT beside the dest (see
        # _backup_path). Overridable so tests don't write into $HOME.
        self.backups_root = Path(backups_root) if backups_root else Path.home() / ".agentconfig-backups"

    # ---- public primitives adapters call -----------------------------------

    def write_file(
        self, dest, content: str, *, harness: str, asset: str, source_ref: str = "",
        kind: str = "file", owned_keys: tuple[str, ...] = (),
    ) -> None:
        """Place a generated text file (CLAUDE.md, AGENTS.md) or a managed-block
        config (`kind="merged"`). Same safety contract either way."""
        dest = Path(dest)
        if self._prepare(dest, unchanged=self._file_matches(dest, content)):
            self._do(lambda: self._atomic_write(dest, content))
        self._record(harness, asset, dest, kind, source_ref, owned_keys)

    def copy_path(self, src, dest, *, harness: str, asset: str) -> None:
        """Copy a source file or directory into place."""
        src, dest = Path(src), Path(dest)
        kind = "dir" if src.is_dir() else "file"
        if self._prepare(dest, unchanged=self._path_matches(src, dest)):
            self._do(lambda: self._copy(src, dest))
        self._record(harness, asset, dest, kind, str(src))

    # ---- shared decision + actions -----------------------------------------

    def _prepare(self, dest: Path, *, unchanged: bool) -> bool:
        """Resolve what to do with an existing target. Returns True if a write
        should follow (False = unchanged no-op)."""
        if dest.is_symlink():
            self._do(dest.unlink)
            self._log("copy", dest)  # replacing a legacy symlink with a copy
        elif dest.exists():
            if unchanged:
                self._log("ok", dest)
                return False
            backup = self._backup_path(dest)
            self._do(lambda: self._replace_into_backup(dest, backup))
            self._log("backup", dest)
        else:
            self._log("new", dest)
        return True

    # ---- I/O helpers (skipped in dry-run via _do) --------------------------

    def _do(self, fn) -> None:
        if not self.dry_run:
            fn()

    @staticmethod
    def _atomic_write(dest: Path, content: str) -> None:
        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp = dest.with_name(f".{dest.name}.tmp-{os.getpid()}")
        tmp.write_text(content)
        os.replace(tmp, dest)

    @staticmethod
    def _copy(src: Path, dest: Path) -> None:
        dest.parent.mkdir(parents=True, exist_ok=True)
        if src.is_dir():
            shutil.copytree(src, dest, ignore=lambda _d, names: [n for n in names if _ignored(n)])
        else:
            tmp = dest.with_name(f".{dest.name}.tmp-{os.getpid()}")
            shutil.copyfile(src, tmp)
            shutil.copymode(src, tmp)
            os.replace(tmp, dest)

    def _backup_path(self, dest: Path) -> Path:
        """Central, timestamped backup location OUTSIDE any harness-scanned
        config tree. A `<name>.backup-*` left next to the dest inside
        `~/.claude/skills/` (or `~/.agents/skills/`) would be walked by the
        loaders and register as a phantom skill/agent — so mirror the dest's
        path under a home-level backups dir instead."""
        dest = dest.absolute()
        rel = Path(*dest.parts[1:])  # drop the leading root anchor
        return self.backups_root / self.stamp / rel

    @staticmethod
    def _replace_into_backup(dest: Path, backup: Path) -> None:
        backup.parent.mkdir(parents=True, exist_ok=True)
        if backup.exists():
            shutil.rmtree(backup) if backup.is_dir() else backup.unlink()
        os.replace(dest, backup)

    # ---- comparison --------------------------------------------------------

    @staticmethod
    def _file_matches(dest: Path, content: str) -> bool:
        return dest.is_file() and not dest.is_symlink() and dest.read_text() == content

    @classmethod
    def _path_matches(cls, src: Path, dest: Path) -> bool:
        if dest.is_symlink() or not dest.exists():
            return False
        if src.is_dir():
            return cls._dirs_equal(src, dest)
        return filecmp.cmp(src, dest, shallow=False)

    @classmethod
    def _dirs_equal(cls, a: Path, b: Path) -> bool:
        ignore = [n for n in {*os.listdir(a), *os.listdir(b)} if _ignored(n)]
        cmp = filecmp.dircmp(a, b, ignore=ignore)
        if cmp.left_only or cmp.right_only or cmp.diff_files or cmp.funny_files:
            return False
        return all(cls._dirs_equal(a / d, b / d) for d in cmp.common_dirs)

    # ---- bookkeeping -------------------------------------------------------

    def _log(self, verb: str, dest: Path) -> None:
        self.result.actions.append((verb, str(dest)))

    def _record(self, harness, asset, dest, kind, source_ref, owned_keys=()) -> None:
        self.result.artifacts.append(
            ManagedArtifact(harness, asset, str(dest), kind, source_ref, tuple(owned_keys))
        )

    def record_failure(self, asset: str, exc: BaseException) -> None:
        self.result.failures.append((asset, f"{type(exc).__name__}: {exc}"))
