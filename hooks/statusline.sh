#!/usr/bin/env bash
# statusLine command: render the prompt status line. Reads the session context
# as JSON on stdin and prints one line: model, current dir, git branch.
# Not a hook — wired via the "statusLine" key in settings.json, kept here so
# all Claude-Code-invoked shell scripts live in one place.

input="$(cat)"
model="$(jq -r '.model.display_name // .model.id // "claude"' <<<"$input" 2>/dev/null)"
dir="$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input" 2>/dev/null)"
[ -n "$dir" ] || dir="$PWD"

branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)"

line="$model  $(basename "$dir")"
[ -n "$branch" ] && line="$line  ($branch)"
printf '%s' "$line"
