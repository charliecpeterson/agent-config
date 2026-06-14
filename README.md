# claude-config

Personal Claude Code configuration: global instructions, coding style,
communication preferences, engineering judgment, and skills. One repo, cloned
to every machine, symlinked into `~/.claude/` by `install.sh`.

## Layout

```
.
├── CLAUDE.md           Global instructions (imports the four files below)
├── userprofile.md      Personal profile: role, expertise boundaries (defer/joint/push-back), compute, references
├── style.md            Coding style and conduct
├── communication.md    Chat tone and format
├── engineering.md      Engineering judgment: pushback, build-vs-buy, anti-over-engineering
├── settings.json       Synced permissions baseline (allow read-only, deny irreversibles)
├── skills/             One folder per skill (each contains SKILL.md + optional references/)
├── agents/             Custom sub-agents shared across skills (deep-planner, writing-architect, llm-council)
├── hooks/              Lifecycle hook scripts + status line (symlinked to ~/.claude/hooks/)
├── notes/              Research notes and scratch documents (not installed anywhere)
├── install.sh          Symlinks files into ~/.claude/
└── .gitignore
```

`settings.json` carries portable policy and automation: a permissions baseline
allowing common read-only commands (git inspection, grep/rg, Slurm queries) and
denying irreversibles (force-push, history rewrites, reading credential files);
the `hooks/` wiring (secret-commit guard, format-on-edit, status line); and the
notification channel. All of it is machine-independent — the hook commands
resolve through the `~/.claude/hooks/` symlink.
Machine-specific state (enabled plugins, model choice, extra permissions) goes
in `~/.claude/settings.local.json`, which Claude Code merges automatically and
which is never synced. Two consequences of the symlink: on a machine's first
install, merge any keys from the backed-up old `settings.json` into
`settings.local.json`; and UI actions that write settings (`/model`, plugin
toggles) will dirty the repo file — move those keys to `settings.local.json`
and `git checkout settings.json`.

## Install on a new machine

```bash
git clone <repo-url> ~/projects/claude-config
cd ~/projects/claude-config
./install.sh
```

The script:
- Symlinks `~/.claude/CLAUDE.md` → `~/projects/claude-config/CLAUDE.md` (and the
  same for `userprofile.md`, `style.md`, `communication.md`, `engineering.md`).
- Symlinks each skill folder under `~/.claude/skills/<name>` → the matching
  folder in this repo.
- Symlinks each sub-agent file under `~/.claude/agents/<name>.md` → the matching
  file in this repo's `agents/` folder. Sub-agents are shared infrastructure
  used by skills like `deep-planner` and `writing-architect`.
- Symlinks `~/.claude/hooks/` → this repo's `hooks/` folder, so the hook and
  status-line scripts that `settings.json` references resolve on every machine.
  See `hooks/README.md` for what each one does.
- Also exports the *portable* skills (those with no Claude-Code sub-agent or MCP
  dependency — see `PORTABLE_SKILLS` in `install.sh`) to `~/.agents/skills/`, the
  directory Codex, pi, and opencode read natively. Crush is pointed at the same
  dir via `skills_paths` in `~/.config/crush/crush.json` (only if Crush is
  already set up). The heavy skills stay Claude-only.
- Flattens the global rules (`userprofile`/`style`/`communication`/`engineering`)
  into `~/.codex/AGENTS.md` and `~/.config/opencode/AGENTS.md`, since those agents
  don't resolve the `@imports` in `CLAUDE.md`. Regenerated each run; a hand-written
  file is backed up once. (pi has no global-rules file, so it gets skills only;
  Crush reads project-level `AGENTS.md`.)
- Backs up any existing real file at the target path to
  `~/.claude/<name>.backup-YYYYMMDD-HHMMSS` before replacing it.
- Skips files that are already correctly symlinked, so the script is safe
  to re-run.
- Prunes symlinks that point into this repo but whose target no longer exists
  (skills or agents deleted from the repo).
- Then prompts, once each, to clone the personal MCP repos (`PERSONAL_MCPS`)
  to `~/mcps/<name>` and `uv sync` them (not registered with Claude Code;
  see "Personal MCP servers" below), and to install the `security-review-deep`
  tools. Run without a terminal, it does the symlinks and takes each prompt's
  default (clone MCPs, skip security tools).

Restart Claude Code after the first install so it picks up the new skills.

## Personal MCP servers

MCP servers I wrote and run locally. They all live under `~/mcps/<name>` —
one predictable place, separate from `~/projects` where active development
happens. `install.sh` offers to clone each and `uv sync` it, but deliberately
does not register any of them with Claude Code: every server is **inactive by
default**. Registering at user scope would load every server's tools into
context in every project, used or not.

Instead, enable a server only in the project where you want it, with local
scope, so its tools load there and nowhere else:

```bash
# run inside the project that needs it
claude mcp add --scope local edamcp -- uv run --directory ~/mcps/edamcp edamcp
claude mcp add --scope local chemtools -- uv run --directory ~/mcps/chemtoolsmcp chemtoolsmcp
claude mcp add --scope local comfyui -- uv run --directory ~/mcps/comfyui_mcp comfyui_mcp

# office-google-mac-mcp is a monorepo; each app is its own server
claude mcp add --scope local word -- uv run --directory ~/mcps/office-google-mac-mcp/packages/office office-mcp word
claude mcp add --scope local excel -- uv run --directory ~/mcps/office-google-mac-mcp/packages/office office-mcp excel
claude mcp add --scope local powerpoint -- uv run --directory ~/mcps/office-google-mac-mcp/packages/office office-mcp powerpoint

# h2mcp (Hoffman2 jobs) is TypeScript; install.sh runs npm install + build
claude mcp add --scope local hoffman2 -- node ~/mcps/h2mcp/dist/index.js
```

Append `--mode local` for edamcp's thin (35-tool) surface. Because the launch
command points at the `~/mcps/<name>` checkout, local edits are live and
`git pull` updates it.

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
| `llm-council` | Pressure-test a real decision through five independent advisor lenses + anonymous peer review + a chairman verdict (Karpathy's LLM Council) |
| `office-mcp` | Driving live Word/Excel/PowerPoint docs through the office MCP tools |
| `presentation-designer` | Slide content and narrative for decks |
| `project-starter` | Bootstrap a new repo from my templates (Python science, Rust CLI, TS tool, MCP server) |
| `recent-research` | Check current community/web sources before answering fast-moving questions |
| `security-review-deep` | Scanner-grounded security audit (distinct from built-in `/security-review`) |
| `session-handoff` | Cross-agent handoff document |
| `stampede3-submit` | Build Slurm sbatch scripts for Stampede3 (queues, ibrun, modules, SU costs) |
| `stampede3-debug` | Diagnose failed/stuck/slow Stampede3 jobs (sacct triage, cluster-specific gotchas) |
| `writing-architect` | Macro-first pipeline for multi-page documents (outline → draft → layered reviews) |

The Stampede3 pair is the pattern for per-cluster skills: submit + debug,
self-contained queue table, cluster-specific failure modes. Hoffman2 is
covered by the `h2mcp` MCP server instead; add a skill pair per cluster as
needed (Anvil next).
