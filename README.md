# claude-config

Personal Claude Code configuration: global instructions, coding style,
communication preferences, engineering judgment, and skills. One repo, cloned
to every machine, symlinked into `~/.claude/` by `install.sh`.

## Layout

```
.
├── CLAUDE.md           Global instructions (imports the three files below)
├── style.md            Coding style and conduct
├── communication.md    Chat tone and format
├── engineering.md      Engineering judgment: pushback, build-vs-buy, anti-over-engineering
├── skills/             One folder per skill (each contains SKILL.md + optional references/)
├── install.sh          Symlinks files into ~/.claude/
└── .gitignore
```

`settings.json` is intentionally not synced — it can hold machine-specific
state (enabled plugins, MCP servers). Per-machine overrides go in
`~/.claude/settings.local.json`, which Claude Code reads automatically.

## Install on a new machine

```bash
git clone <repo-url> ~/projects/claude-config
cd ~/projects/claude-config
./install.sh
```

The script:
- Symlinks `~/.claude/CLAUDE.md` → `~/projects/claude-config/CLAUDE.md` (and the
  same for `style.md`, `communication.md`, `engineering.md`).
- Symlinks each skill folder under `~/.claude/skills/<name>` → the matching
  folder in this repo.
- Clones each personal MCP repo (see `PERSONAL_MCPS` in the script) to
  `~/projects/<name>` and runs `uv sync`, without registering it with Claude
  Code. See "Personal MCP servers" below.
- Backs up any existing real file at the target path to
  `~/.claude/<name>.backup-YYYYMMDD-HHMMSS` before replacing it.
- Skips files that are already correctly symlinked, so the script is safe
  to re-run.

Restart Claude Code after the first install so it picks up the new skills.

## Personal MCP servers

MCP servers I wrote and run locally (e.g. `edamcp`). `install.sh` clones each
to `~/projects/<name>` and runs `uv sync`, but deliberately does not register
them with Claude Code. Registering at user scope would load every server's
tools into context in every project, used or not.

Instead, register a server only in the project where you want it, with local
scope, so its tools load there and nowhere else:

```bash
# run inside the project that needs it
claude mcp add --scope local edamcp -- uv run --directory ~/projects/edamcp edamcp
```

Append `--mode local` for edamcp's thin (35-tool) surface. Because the launch
command points at the `~/projects/edamcp` checkout, your local edits are live
and `git pull` updates it.

To add another personal MCP, append a `"name|git-url"` line to `PERSONAL_MCPS`
in `install.sh`, re-run it, then use the same `claude mcp add --scope local`
pattern in your projects.

## Editing

Edit files directly in this repo. The symlinks mean changes take effect
immediately in `~/.claude/`. Commit and push when you're happy; on other
machines, `git pull` and the changes propagate.

## Skills

| Skill | Purpose |
|---|---|
| `bug-hunter` | Disciplined debugging — root cause, not symptom |
| `code-review-deep` | Tool-grounded review — whole-codebase assessment by default (Continue/Refactor/Rebuild), or a deep scoped change review when you name a PR/commit (distinct from built-in `/code-review`) |
| `deep-planner` | Exhaustive one-question-at-a-time planning sessions |
| `dyslexia-friendly` | Formats all output for dyslexic-friendly reading |
| `editor` | Critique-only feedback on drafts (no rewriting) |
| `human-writer` | Generate or rewrite prose, always non-AI-sounding |
| `presentation-designer` | Slide content and narrative for decks |
| `security-review-deep` | Scanner-grounded security audit (distinct from built-in `/security-review`) |
| `session-handoff` | Cross-agent handoff document |
| `diffusion-skills/skills/*` | Prompting skills for image and video models (Flux, Qwen, Z-Image, Wan, LTX, Illustrious) |

The diffusion-skills folder is a container — each prompt-skill inside it
installs as a top-level skill in `~/.claude/skills/` (e.g., `prompt-flux`
becomes its own skill).
