# hooks

Shell scripts Claude Code invokes at lifecycle events, plus the status line.
`install.sh` symlinks this whole directory to `~/.claude/hooks/`, so
`settings.json` can reference `~/.claude/hooks/<script>` on every machine
regardless of where the repo is cloned. All scripts are portable (macOS +
Linux) and degrade to a no-op when a tool they'd call is absent.

| Script | Wired as | Fires on | Does |
|---|---|---|---|
| `block-secret-commit.sh` | `hooks.PreToolUse` (Bash, `if git commit*`) | a `git commit` | denies the commit if staged files look like secrets (`.env`, `*.pem`, `id_rsa`, …) |
| `format-edited-file.sh` | `hooks.PostToolUse` (Write\|Edit) | Claude writing/editing a file | formats it — but only with a formatter the project adopts (gofmt/rustfmt always; ruff/black/prettier only when project config exists) |
| `statusline.sh` | `statusLine` | prompt redraw | prints `model  dir  (branch)` |

Notification on idle / permission-waiting is handled by the built-in
`preferredNotifChannel` setting, not a Stop hook — a Stop hook fires every
turn and would spam.

Edit a script and the change is live (symlink). Review or disable hooks
interactively with `/hooks`.
