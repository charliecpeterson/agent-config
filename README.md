# agent-config

One source of truth for my AI-agent setup — global instructions, coding style,
skills, sub-agents, MCP servers, and permissions — **rendered into each
harness's native config format** by a small generator. Edit once, run the
installer, and the right files land for Claude Code, Codex, opencode, Crush,
and pi.

The content (the four rule files, `skills/`, `agents/`, `hooks/`,
`settings.json`) is the source; every harness output is generated from it. No
harness is privileged — Claude is just one adapter among five.

## How it works

`install.sh` is a thin bootstrap: it clones/builds the personal MCP servers
(bash, where that work belongs), then hands off to the **`agentconfig`
generator** (Python, standard library only — no venv, runs on any `python3 >=
3.11`). The generator:

1. Loads `manifest.toml` (the control plane: harnesses, MCP servers + their
   per-harness targeting, which skills are portable).
2. Detects which harnesses are actually installed and **skips the rest** — it
   never creates `~/.codex` etc. for a tool you don't use.
3. For each present harness, an **adapter** renders that harness's native
   format, writing through a safe-I/O layer: atomic writes, back up a *changed*
   file before replacing it, skip an unchanged one (idempotent re-runs),
   `--check` for a dry run.

Two rules keep it from ever clobbering your hand edits:

- **Separate files** where it can — `CLAUDE.md`, each harness's `AGENTS.md` /
  `CRUSH.md`. The generator owns the whole file.
- **Surgical merges** into shared configs it doesn't own: a **comment-preserving
  managed block** for Codex's `config.toml` (which Codex co-manages), and a
  **keyed deep-merge** for JSON configs (`opencode.json`, `crush.json`) that
  preserves every other key and refuses rather than clobber a file it can't
  parse. Your providers, models, and existing servers survive untouched.

What renders where — and the deliberate gaps — is in **[`SUPPORT.md`](SUPPORT.md)**.
Short version: rules + skills + MCP port everywhere they can; permissions port
faithfully to Claude and opencode (command-pattern models) and are an honest
gap where a harness can't express them (Codex/Crush). Every gap is a verified
decision, not unfinished work.

## Copies, not symlinks

The installer **copies** files into place rather than symlinking. That keeps the
installed config **decoupled from where this repo lives** — move, rename, or
re-clone the repo and everything keeps working. The tradeoff: repo edits aren't
live until you re-run (the same model the MCPs already use). `./install.sh
--config-only` re-applies config without touching the MCP checkouts.

## Install on a new machine

```bash
git clone <repo-url> ~/projects/agent-config
cd ~/projects/agent-config
./install.sh                 # config for all installed harnesses, then MCPs
./install.sh --config-only   # config only; skip MCP/repo cloning
./install.sh --check         # dry run: show what would change
```

Restart your agents afterward so they pick up the new skills. Re-run after a
`git pull` to apply updates.

## Layout

```
.
├── userprofile.md / style.md / communication.md / engineering.md
│                       The neutral rule source (topic split). CLAUDE.md and
│                       each AGENTS.md are GENERATED from these.
├── settings.json       Claude permissions + hooks baseline; also the
│                       permission source other adapters translate from.
├── skills/             One folder per skill (SKILL.md + optional references/).
├── agents/             Sub-agents for the Claude-only skills (deep-planner,
│                       writing-architect, doc-grounded, …).
├── hooks/              Hook scripts + status line (Claude).
├── manifest.toml       Control plane: harnesses, MCP servers + targeting,
│                       portable-skill list, the CLAUDE.md preamble.
├── agentconfig/        The generator (stdlib Python): core, adapters/, the
│                       reconciler, the managed-state store.
├── tests/  test.sh     Stdlib unittest suite (run ./test.sh).
├── install.sh          Bootstrap: clone/build MCPs, then run the generator.
├── SUPPORT.md          The harness support matrix.
└── PROJECT_PLAN.md     Design decisions + roadmap.
```

Machine-specific Claude state (enabled plugins, model choice, extra
permissions) goes in `~/.claude/settings.local.json`, which Claude merges
automatically and which is never synced. Since UI actions (`/model`, plugin
toggles) edit the installed *copy* of `settings.json`, just re-run the installer
to restore the synced baseline.

## The manifest

`manifest.toml` is the only thing you edit to change *where* and *what* gets
registered (the content lives in the rule/skill/agent files). Notably, MCP
servers declare per-harness targeting — the same idiom as the per-machine
extras:

```toml
[mcp.transcribemcp]
command = "~/mcps/bin/transcribemcp-run"   # secrets stay in the MCP's own .env
targets = ["codex", "opencode", "crush"]   # not Claude (manual) or pi (no native MCP)
```

The generator registers each MCP into the native config of every harness in its
`targets`, pointing at the wrapper command — never writing a secret into a
generated file.

## Personal MCP servers

MCP servers I wrote, under `~/mcps/<name>`. `install.sh` clones each and
`uv sync`s it. They're auto-registered into the harnesses named in their
manifest `targets`. **Claude registration stays manual and per-project** by
design — user-scope registration would load every server in every project:

```bash
# enable a server only in the project that needs it
claude mcp add --scope local transcribe -- ~/mcps/bin/transcribemcp-run
claude mcp add --scope local edamcp     -- uv run --directory ~/mcps/edamcp edamcp
# office-google-mac-mcp is a monorepo; each app is its own server
claude mcp add --scope local word -- uv run --directory ~/mcps/office-google-mac-mcp/packages/office office-mcp word
```

To add another MCP: append a `"name|git-url"` line to `PERSONAL_MCPS` in
`install.sh` (cloning), and an `[mcp.<name>]` block to `manifest.toml`
(registration + targeting).

## Editing

Edit the source files (rules, `skills/`, `agents/`, `settings.json`,
`manifest.toml`), then re-run `./install.sh` (or `--config-only`) to render the
changes into each harness. Commit and push; on other machines, `git pull` then
re-run.

## Skills

| Skill | Purpose |
|---|---|
| `bug-hunter` | Disciplined debugging — root cause, not symptom |
| `code-review-deep` | Tool-grounded review — whole-codebase assessment by default (Continue/Refactor/Rebuild), or a deep scoped change review when you name a PR/commit (distinct from built-in `/code-review`) |
| `deep-planner` | Exhaustive one-question-at-a-time planning sessions |
| `doc-grounded` | Answer tool/config/API questions from a source you point at (docs URL or local corpus) and cite the exact location, instead of from stale memory |
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
self-contained queue table, cluster-specific failure modes. Hoffman2 is covered
by the `h2mcp` MCP server instead; add a skill pair per cluster as needed
(Anvil next).
