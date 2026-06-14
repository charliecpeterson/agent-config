#!/usr/bin/env bash
# PostToolUse hook (Write|Edit): format the file Claude just touched — but only
# with a formatter the project actually adopts. Gating on project config is the
# point: it keeps a one-line edit from turning into a whole-file reformat in a
# repo that doesn't use that tool. Always exits 0; formatting never blocks.
#
# gofmt and rustfmt are canonical and idempotent, so they run whenever present.
# Python (ruff/black) and JS/TS (prettier) only run when the project opts in.

f="$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)"
[ -n "$f" ] && [ -f "$f" ] || exit 0
dir="$(dirname "$f")"

find_up() {
  local d="$1" name="$2"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -e "$d/$name" ] && { echo "$d/$name"; return 0; }
    d="$(dirname "$d")"
  done
  return 1
}

has_ruff() {
  find_up "$dir" ruff.toml >/dev/null && return 0
  find_up "$dir" .ruff.toml >/dev/null && return 0
  local p; p="$(find_up "$dir" pyproject.toml)" && grep -q '\[tool\.ruff' "$p"
}
has_black() {
  local p; p="$(find_up "$dir" pyproject.toml)" && grep -q '\[tool\.black\]' "$p"
}
has_prettier() {
  local n p
  for n in .prettierrc .prettierrc.json .prettierrc.yml .prettierrc.yaml .prettierrc.js prettier.config.js; do
    find_up "$dir" "$n" >/dev/null && return 0
  done
  p="$(find_up "$dir" package.json)" && grep -q '"prettier"' "$p"
}

case "$f" in
  *.py)
    if command -v ruff >/dev/null 2>&1 && has_ruff; then ruff format -q "$f"
    elif command -v black >/dev/null 2>&1 && has_black; then black -q "$f"
    fi ;;
  *.rs) command -v rustfmt >/dev/null 2>&1 && rustfmt "$f" ;;
  *.go) command -v gofmt   >/dev/null 2>&1 && gofmt -w "$f" ;;
  *.js | *.jsx | *.ts | *.tsx | *.css | *.scss)
    command -v prettier >/dev/null 2>&1 && has_prettier && prettier --write --log-level silent "$f" ;;
esac
exit 0
