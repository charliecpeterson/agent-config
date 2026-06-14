#!/usr/bin/env bash
# PreToolUse hook (Bash / git commit): refuse a commit that stages obvious
# secret files. Complements the Read-deny rules in settings.json — those stop
# the model reading credentials, this stops it committing them.
#
# Emits a PreToolUse "deny" decision (JSON on stdout) when staged paths look
# like secrets; silent exit 0 otherwise. Never hard-fails the turn.

payload="$(cat)"
cmd="$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null)"

case "$cmd" in
  *git*commit*) ;;
  *) exit 0 ;;
esac

# Honor `git -C <dir> commit`; default to the session cwd.
dir="$(awk '{for (i = 1; i < NF; i++) if ($i == "-C") print $(i + 1)}' <<<"$cmd" | head -1)"
[ -n "$dir" ] || dir="$PWD"

staged="$(git -C "$dir" diff --cached --name-only 2>/dev/null)"
[ -n "$staged" ] || exit 0

secret_re='(^|/)(\.env(\..+)?|\.netrc|id_(rsa|dsa|ecdsa|ed25519)|.+\.(pem|key|p12|pfx|pkcs12|keystore|jks)|credentials(\.json)?|.*service-account.*\.json)$'
allow_re='\.env\.(example|sample|template)$|\.pub$'

offenders=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if grep -Eq "$secret_re" <<<"$f" && ! grep -Eq "$allow_re" <<<"${f##*/}"; then
    offenders+="  $f"$'\n'
  fi
done <<<"$staged"

[ -n "$offenders" ] || exit 0

reason="Refusing to commit — these staged files look like secrets:"$'\n'"$offenders"$'\n'"Unstage them, or commit yourself if this is deliberate."
jq -n --arg r "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
