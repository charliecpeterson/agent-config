# Working on agent-config

This repo is the source of truth for the AI-agent setup; the `agentconfig`
generator renders it into each harness's native config. Background: README.md.
Design decisions: PROJECT_PLAN.md. Harness support matrix: SUPPORT.md.

## Rules for edits

- Edit the sources: `userprofile.md`, `style.md`, `communication.md`,
  `engineering.md`, `skills/`, `agents/`, `settings.json`, `manifest.toml`.
  Never edit generated outputs under `~/.claude`, `~/.codex`,
  `~/.config/opencode`, etc.; the next `./install.sh` overwrites them.
- After editing content: run `./test.sh`, then `./install.sh --config-only`
  to re-render (`--check` for a dry run).
- `agentconfig/` is stdlib-only Python (3.11+): no dependencies, no venv.
- Keep `skills/*/SKILL.md` under ~500 lines; push detail into the skill's
  `references/` dir.
- `manifest.toml` alone controls where things land: harnesses, MCP targeting,
  portable skills, machine host map.
