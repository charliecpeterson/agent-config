# Harness support matrix

What `agent-config` renders to each harness, and what it deliberately doesn't.
Every gap below is a **verified decision** (checked against current docs / a live
install), not unfinished work — see the rationale and `PROJECT_PLAN.md`.

Legend: ✅ ported · ✅ⁿ native (the harness reads a shared dir, no work needed) ·
**gap** (can't port faithfully — documented) · n/a (no source) · ~ unverified.

| Asset | Claude | Codex | opencode | Crush | pi |
|-------|:--:|:--:|:--:|:--:|:--:|
| **Rules** (instructions) | ✅ `CLAUDE.md` | ✅ `AGENTS.md` | ✅ `AGENTS.md` | ✅ `CRUSH.md` | ✅ `~/.pi/agent/AGENTS.md` |
| **Machine profile** | ✅ `machines.md` import | ✅ in `AGENTS.md` | ✅ in `AGENTS.md` | ✅ in `CRUSH.md` | ✅ in `AGENTS.md` |
| **Skills** | ✅ `~/.claude/skills` | ✅ `config.toml` paths | ✅ `~/.agents/skills` + targeted `~/.config/opencode/skills` via `opencode-agent` | ✅ⁿ `~/.agents/skills` + `~/.claude/skills` | ~ |
| **MCP servers** | manual¹ | ✅ `[mcp_servers]` | ✅ `mcp` | ✅ `mcp` | **gap** (no native MCP) |
| **Permissions** | ✅ `settings.json` | **gap** | ✅ `permission.bash` | **gap** | **gap** |
| **Subagents** | ✅ `~/.claude/agents` | ✅ `code-skeptic.toml` | ✅ `code-skeptic.md` | **gap** | **gap** |
| **Hooks** | ✅ `settings.json` | **gap** | **gap** | **gap** | **gap** |

¹ Claude MCP registration stays manual (`claude mcp add --scope local`) by
design — user-scope registration loads every server in every project.

## Why the gaps

- **Permissions, Codex & Crush.** Neither has a command-pattern deny mechanism:
  Codex has only coarse sandbox modes + a `default_permissions` profile (whose
  file-denies would commandeer the whole policy); Crush has only an
  `allowed_tools` name list. So the bash deny-floor (`git push --force`,
  `rm -rf /`, …) can't be expressed → gap, not an approximation (OQ3 fail-safe).
  **opencode** is the exception — its `permission.bash` command-glob model maps
  Claude's allow/deny faithfully. (`Read()` credential denies are a partial gap
  even there — opencode governs bash/edit, not file reads.)
- **MCP, pi.** pi ships without native MCP ("No MCP"; extension-only).
- **Subagents.** The 14 agents include `code-skeptic`, rendered to Codex and
  opencode because the portable `bug-scan` skill invokes it. The other 13 are
  infrastructure for Claude-only skills (deep-planner / writing-architect /
  llm-council / doc-grounded / doc-sync), so porting them would create inactive
  configuration.
- **Hooks.** The hook scripts are bound to Claude's hook I/O contract
  (`.tool_input.*` in, `hookSpecificOutput` out); run by another harness they
  silently no-op. Registering them would be a false safety signal. Porting
  needs harness-aware scripts (a separate effort).

## Verification provenance (caught real bugs)

Verifying each `(verify)` cell against current docs / live installs corrected
three wrong assumptions baked into the old `install.sh`:

- Codex does **not** read `~/.agents/skills` (skills register via `config.toml`)
  — skills weren't reaching Codex.
- opencode discovers both `~/.agents/skills` and `~/.claude/skills`, and supports
  global Markdown subagents under `~/.config/opencode/agents/`. The managed
  `opencode-agent` launcher disables the latter, preserving the portable-skill
  boundary and its smaller skill inventory.
- Current Codex releases run subagent workflows by default and load custom
  TOML agents under `~/.codex/agents/`; only `code-skeptic` is targeted there.
- pi **does** read a global `~/.pi/agent/AGENTS.md` — it was getting no global
  rules, not "skills-only" as assumed.
