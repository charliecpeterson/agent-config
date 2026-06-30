#!/usr/bin/env bash
# check-docs.sh — deterministic, no-LLM documentation freshness lint.
#
# Catches the highest-frequency doc drift cheaply, on every commit:
#   1. Link/path integrity — dead local links and missing referenced files,
#      via lychee (offline by default; DOCS_LINT_WEB=1 also checks URLs).
#   2. Denylist — tokens that must never reappear in the docs once cut from
#      the code (old env vars, deleted crates, dead filenames). Listed in a
#      .docs-lint file at the repo root: one POSIX extended-regex per line,
#      '#' comments and blank lines ignored. Changelog-style files are exempt
#      (history is allowed to mention removed things). No .docs-lint => the
#      denylist step is skipped.
#
# Non-zero exit on any failure. For CI and an optional pre-commit hook. The
# periodic, semantic counterpart is the `doc-sync` skill (LLM audit); this is
# the always-on layer.
set -uo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$root" || exit 1

# Tracked docs, minus vendored/build trees. (bash-3.2-safe: no mapfile.)
docs=()
while IFS= read -r f; do docs+=("$f"); done < <(
  git ls-files '*.md' '*.markdown' '*.qmd' '*.rst' '*.mdx' '*.adoc' \
    | grep -vE 'node_modules/|target/|vendor/|third_party/|\.venv/' || true
)
if [ "${#docs[@]}" -eq 0 ]; then echo "check-docs: no docs found."; exit 0; fi

status=0

# 1. Link / path integrity ---------------------------------------------------
if command -v lychee >/dev/null 2>&1; then
  args=(--no-progress)
  [ "${DOCS_LINT_WEB:-0}" = "1" ] || args+=(--offline)
  echo "check-docs: link check — ${#docs[@]} docs ($([ "${DOCS_LINT_WEB:-0}" = "1" ] && echo "with URLs" || echo "offline"))"
  if ! lychee "${args[@]}" "${docs[@]}"; then
    echo "check-docs: broken links/paths (see above)" >&2; status=1
  fi
else
  echo "check-docs: lychee not found — skipping link check (install: 'cargo install lychee' or 'brew install lychee')" >&2
fi

# 2. Denylist ----------------------------------------------------------------
if [ -f .docs-lint ]; then
  # History files may legitimately name removed things.
  deny_docs=()
  for f in "${docs[@]}"; do
    case "$(basename "$f")" in
      CHANGELOG*|HISTORY*|NEWS*|RELEASES*) ;;
      *) deny_docs+=("$f") ;;
    esac
  done
  hits=0
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    case "$pat" in \#*) continue ;; esac
    if [ "${#deny_docs[@]}" -gt 0 ] && m="$(grep -InE -- "$pat" "${deny_docs[@]}" 2>/dev/null)"; then
      echo "check-docs: removed token /$pat/ reappeared:" >&2
      printf '%s\n' "$m" | sed 's/^/    /' >&2
      hits=1
    fi
  done < .docs-lint
  [ "$hits" -eq 0 ] && echo "check-docs: denylist clean (${#deny_docs[@]} docs)"
  [ "$hits" -eq 0 ] || status=1
else
  echo "check-docs: no .docs-lint denylist (create one to guard removed tokens)"
fi

if [ "$status" -eq 0 ]; then echo "check-docs: passed"; else echo "check-docs: FAILED" >&2; fi
exit "$status"
