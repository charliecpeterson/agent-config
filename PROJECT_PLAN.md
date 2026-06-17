# Project Plan: harness-neutral agent config system (claude-config redesign)

> Living document. Updated incrementally by the deep-planner skill.
> Last updated: 2026-06-17
> Current phase: Phase 1 complete; Phase 2 (other adapters) next

## Goal                                                    (always)
Evolve claude-config from a Claude-Code-centric config repo into a
harness-neutral, single-source-of-truth system that installs prompts,
skills, subagents, MCP servers, hooks, and permissions across Claude
Code + Codex + opencode + Crush + pi — each rendered to its native
format — with a hardened installer and a harness-neutral repo name.

## Archetype                                               (always)
- **Primary**: library/CLI (an installer / config-tooling repo).
- **Secondary**: pipeline — the install is a render-and-sync pipeline;
  idempotency, partial-failure handling, and re-run semantics are
  first-class (directly relevant to the "harden" goal).
- **Expertise calibration**: joint. Personal tooling + shell/installer
  engineering is the user's sysadmin wheelhouse. Conductor leads on
  render-architecture and code quality; defers to user on which
  harnesses/workflows matter. Push hardest on over-engineering (a
  config installer grows tentacles fast).

## Scope                                                   (always)
### In scope
- Single canonical source → per-harness render of each asset type:
  instructions/prompt, skills, subagents, MCP servers, hooks,
  permissions. Targets: Claude Code, Codex, opencode, Crush, pi.
- **Pluggable per-harness adapter** layer so a 6th harness is a small,
  well-defined addition (justified: 5 targets already).
- **Operational hardening**: idempotent/dry-run install (extend
  `CHECK_ONLY`), schema/lint validation of generated configs, a
  clean-machine install test, partial-failure semantics, no clobbering
  local edits.
- Fix the latent bug: skills don't currently reach Codex (it doesn't
  read `~/.agents/skills`).
- Repo rename to a harness-neutral name.

### Out of scope (unless promoted)
- Harnesses beyond the five (designed-for, not built).
- Any GUI / TUI / daemon / auto-update mechanism.
- Managing secrets/credentials across machines (config only).

## Decision Log                                            (always)
- **[2026-06-17] Session mode: decision-mapping**
  - **Choice**: decision-mapping (not a lighter roadmap).
  - **Why**: five genuine architectural forks ahead, the canonical
    source format being load-bearing for all others.

- **[2026-06-17] Scope ambition: maximal**
  - **Choice**: render-parity + pluggable adapters + CI/tests/validation.
  - **Why**: user maintains this across machines as load-bearing
    workflow infra; 5 harnesses justify the adapter abstraction.
  - **Watch**: over-engineering within scope — phase the adapters,
    keep CI lean.

- **[2026-06-17] D1: Canonical source format = neutral content files**
  - **Choice**: the topic files (userprofile/style/communication/
    engineering, + a manifest) are the source of truth. BOTH
    `CLAUDE.md` and `AGENTS.md` are generated render targets; Claude is
    treated as just another adapter, no privileged format.
  - **Why**: symmetry — the adapter layer has no special case; keeps
    the meaningful topic split; cost is trivial (generated `CLAUDE.md`
    can still be `@import` lines pointing at the canonical files).
  - **Alternatives considered**: keep `*.md`+Claude-native (status quo,
    privileges Claude's format forever); AGENTS.md-as-source (collapses
    the topic split, AGENTS.md loosely specified).
  - **Revisit if**: maintaining the Claude render proves to cost more
    than the symmetry is worth.

- **[2026-06-17] D2: Render mechanism = generator + adapter modules**
  - **Choice**: a small build tool reads neutral source + a manifest;
    one adapter module per harness emits its native config (TOML/JSON/
    npm/symlinks) with merge-not-clobber. `install.sh` becomes a thin
    bootstrap (clone → run generator → place files).
  - **Why**: targets are structured (Codex TOML, opencode/Crush JSON,
    pi npm) and must merge into hand-edited configs (D5) — bash can't do
    that safely. Adapters are unit-testable; a 6th harness is one new
    module. Matches the chosen adapter+CI scope.
  - **Alternatives considered**: bash orchestrator + structured helpers
    (weaker abstraction, hard to test); pure bash+jq (TOML pain, not
    modular — contradicts scope).
  - **Revisit if**: the adapter set stabilizes at ~2 harnesses and the
    generator's overhead stops paying for itself.
  - **D2a: generator language = Python, stdlib-only.** Primary language,
    present on every target by default, `uv` already a repo dep.
    Constrained to stdlib (tomllib reads TOML 3.11+; hand-format or
    vendor a tiny TOML writer) so system `python3` runs it with no venv
    bootstrap. Alternatives: Go/Rust single binary (zero runtime dep but
    build/release overhead, not primary language).

- **[2026-06-17] D3: Parity depth = native-first + full permissions port**
  - **Principle**: render an asset to a harness only where natively
    supported; shim only when high-value and low-maintenance; else a
    **named gap** in a published support matrix. Coverage: rules→all
    (fix Crush+pi), skills→all (fix Codex path), subagents→Claude/Codex
    `[agents]`/opencode (Crush/pi verify), MCP→all (mechanism=D4),
    hooks→Claude/Codex `[hooks]` (rest gap), commands→opencode/Codex.
  - **Permissions choice**: **full port** to each harness's native model
    (deny-floor + allow-list), not just the safety floor.
  - **Why (permissions)**: user wants the credential/force-push safety
    net *and* convenience everywhere; security-adjacent, worth the cost.
  - **Consequence flagged**: permissions is the highest-complexity
    adapter — Claude command-patterns → Codex approval-modes / opencode
    wildcard / Crush struct don't map 1:1. Mappings must be explicit and
    validated (D8); a mis-map is a silent safety hole.
  - **Alternatives considered**: safety-floor-only (less work, recommended
    but declined); Claude-only (loses the net elsewhere).
  - **Revisit if**: a permission mapping proves unmaintainable for a
    given harness — degrade that one to safety-floor-only.

- **[2026-06-17] D4: MCP registration = auto-register, per-MCP targeting**
  - **Choice**: render registers MCPs into each harness's native config
    by default, with an optional per-MCP harness filter in the manifest
    (same idiom as the `mlx=`/`cuda=` per-machine extras).
  - **Why**: parity on a fresh machine without manual wiring, but
    opt-out precision to control tool-bloat (not every MCP belongs in
    every harness). Reuses an existing manifest idiom, not new machinery.
  - **Alternatives considered**: register-all-everywhere (tool-bloat);
    keep-manual (no parity, status quo).
  - **Revisit if**: tool-bloat shows up even with targeting → add a
    per-harness enable/disable default.

- **[2026-06-17] D5: Reconciliation = separate-file-first, keyed-merge fallback**
  - **Choice**: where a harness supports config layering/includes, the
    generator owns its own file and the main config imports it; where
    it's a single shared file, keyed deep-merge (owns declared keys,
    preserves the rest). Always tracks exactly what it manages.
  - **Why**: never clobber hand edits (the trust-killer); physical file
    ownership makes prune (D7) trivial; managed-key tracking is the
    enabler for both merge-safety and prune.
  - **Alternatives considered**: uniform deep-merge (simpler, ownership
    only in metadata); overwrite-whole-files (clobbers, rejected).
  - **Revisit if**: a harness supports neither includes nor safe merge.

- **[2026-06-17] D6/D8: Hardening contract (accepted)**
  - **D6 re-run safety**: idempotent; `--check` dry-run (extends
    `CHECK_ONLY`); partial-failure *continues* + end-of-run failure
    summary; atomic writes (temp+move); back up before overwrite
    (`STAMP`). Render only configures harnesses actually present
    (skip-absent, not error — install.sh already does this for Crush).
  - **D8 validation/CI**: per-adapter unit tests; parse/schema-validate
    every generated config; clean-machine smoke test in CI (container →
    install → assert). Runs locally (`./test.sh`) + on push (GitHub
    Actions). This is the safety net for the risky permissions mappings.

- **[2026-06-17] D7: Prune = none (manual), but report stale**
  - **Choice**: no automated deletion; user cleans up by hand. As a
    zero-risk aid, the generator *reports* managed artifacts no longer in
    source (it tracks them via D5) without deleting them.
  - **Why**: user prefers control over deletions (sysadmin instinct).
  - **Consequence**: the stale-artifact problem persists across harnesses;
    the stale-report mitigates discoverability.
  - **Revisit if**: stale cruft accumulates faster than manual cleanup.

- **[2026-06-17] D9: Schema evolution = light**
  - **Choice**: each adapter records the harness version it was tested
    against; D8 validation catches malformed output. No version-detection
    or compat-matrix machinery.
  - **Why**: solo-maintained; breakage is noticed; holds the
    over-engineering line.

- **[2026-06-17] D1b: Manifest format = TOML**
  - **Choice**: the manifest (asset→harness matrix, MCP targeting,
    per-skill/agent portability) is TOML, read-only via stdlib
    `tomllib`. Human-friendly (comments, tables), no writer needed.
  - **Alternatives**: JSON (no comments); Python file (mixes data+logic,
    over-engineering risk).

- **[2026-06-17] D10: Repo name = agent-config**
  - **Choice**: rename `claude-config` → `agent-config`. Neutral,
    consistent with `~/.agents/skills` + the AGENTS.md ecosystem.
  - **Blast radius**: repo dir, GitHub repo, install.sh self-refs,
    machine bootstrap clones, the README framing.

- **[2026-06-17] Hidden decisions (Phase 4, accepted defaults)**
  - No secrets in generated configs (MCP registration points at the
    `~/mcps/bin/<name>-run` wrapper; secrets stay in the MCP `.env`).
  - Symlink-live for Claude assets; copy-on-render for generated
    TOML/JSON configs (can't symlink a merged file → re-run to update).
  - Skip-absent harnesses (render only what's installed; never error).

- **[2026-06-17] REVISION: copy not symlink for Claude; rename done early**
  - **Supersedes** the hidden decision "symlink-live for Claude." Claude
    assets are now **copied** into `~/.claude`, like every other harness
    (you can't symlink a merged config, so copy makes all placement
    uniform — Claude stops being the one special case). Edits apply on
    re-run, not live; an opt-in `--link`/dev mode for live authoring is
    deferred to the generator (Phase 1).
  - **Why**: the symlink coupled `~/.claude` to the repo's path (35 live
    symlinks); a stable snapshot is also safer for a repo edited by AI
    agents (branch/stash/half-edit doesn't mutate the running config).
  - **Done early (ahead of Phase 3)**: converted `install.sh`
    `link_file`→`place_file` (copy, idempotent, backup-on-change), added
    `--config-only`, ran it to convert all 35 symlinks to copies, then
    moved the repo `~/projects/claude-config`→`~/projects/agent-config`
    and re-pointed origin to `github.com/charliecpeterson/agent-config`.
    The copy conversion is what made the move safe (verified `~/.claude`
    survived the move). Old `claude-config` GitHub repo now orphaned.
  - **Remnant**: the deeper multi-harness render is still Phase 1–2; the
    Phase-1 generator inherits this copy decision.

## Open Questions (the forks to map)                       (always)
1. **Canonical source format** (most upstream): keep authoring the
   `*.md` rule files + generate per-harness, or flip to AGENTS.md as
   the source of truth? Affects every harness and every asset.
2. **Parity depth per harness**: which asset types to render to which
   harness, given the capability matrix (some are native, some
   shimmable, some impossible).
3. **MCP registration**: auto-register MCP servers into each harness's
   config, or keep the current deliberate "install but don't register"?
4. **What "harden" concretely means**: the specific robustness/test
   guarantees to commit to.
5. **Repo name**: the harness-neutral name (cheapest, settle last).

## Architecture                                            (Phase 8 ran)

A render-and-place pipeline with a pluggable tail. Stdlib-only Python,
right-sized for 5 harnesses — one real abstraction (the adapter), no
framework.

### Components
- **Bootstrap (`install.sh`, demoted)**: the only surviving bash. Clones
  `PERSONAL_MCPS`/`PERSONAL_REPOS`, runs `uv sync` with per-machine
  extras, writes `~/mcps/bin/<name>-run` wrappers, seeds `.env`, then
  locates `python3` (≥3.11) and runs the generator. MCP *building* stays
  bash (process orchestration); MCP *registration* moves to the generator.
- **Generator core (`agentconfig/`)**: loads manifest, detects present
  harnesses (skip-absent), dispatches each renderable (asset, harness)
  cell to its adapter. Owns the cross-cutting safety contract: atomic
  write (temp + `os.replace`), backup-before-overwrite (`STAMP`),
  `--check` dry-run, partial-failure collection + end summary, the
  managed-state store.
- **Adapters (`agentconfig/adapters/<harness>.py`)**: the pluggable tail;
  Claude is one of them, not privileged. Fixed contract: `HARNESS`,
  `TESTED_AGAINST` (D9 version pin), `is_present(env)`, `emit(asset,
  source, manifest, ctx) -> list[ManagedArtifact]`, `validate(artifact)`.
  Adapters never open files directly — they call `ctx` (RenderContext)
  primitives. A 6th harness = new module + manifest block + test; no core
  changes. Discovery = explicit registry dict (OQ5).
- **Reconciler (`reconcile.py`)**: the two D5 strategies centralized —
  separate-file ownership (own a file, main config includes it) and
  keyed deep-merge (own declared keys, preserve the rest). Makes
  "never clobber hand edits" a system property.
- **Managed-state store (`~/.agent-config/state.json`)**: records what's
  owned per harness; drives merge-safety and the stale report. Machine-
  local, regenerable (OQ4). Never an authority to delete (D7).
- **Validation/CI (`tests/`, `test.sh`, GitHub Actions)**: per-adapter
  unit tests, re-parse/schema-validate every generated config, clean-
  machine smoke test (container → bootstrap → assert).

### Data flow
neutral source (content files + `manifest.toml`) → manifest loader
(typed, fail-fast) → generator core (detect present harnesses) → per
harness, per renderable asset: `adapter.emit()` → reconciler (separate-
file | keyed-merge) → atomic write + backup → `adapter.validate()` →
record `ManagedArtifact` → state.json. Then: state diff vs this run →
**stale report** (no delete) → end-of-run summary.

`CLAUDE.md` and `AGENTS.md` are both generated (D1); Claude assets are
symlinked (live), generated TOML/JSON are written copies (re-run to
update).

### Manifest (TOML, read-only via tomllib)
Tables: `[harness.<name>]` (config path, detect rule, reconcile strategy,
`tested_against`); `[matrix.<asset>]` (native|shim|gap per harness — the
published support matrix is generated from this); `[skills.<name>]` /
`[subagents.<name>]` (`targets = [...]`, lifts `PORTABLE_SKILLS` into
data); `[mcp.<name>]` (wrapper path, per-machine `extras`, harness
`targets`); `[permissions]` (one **neutral** allow/deny block — each
adapter translates it; translation is code, not data, since mappings
aren't 1:1).

### Trust boundaries
- **No secrets in generated configs**: MCP registration points at the
  `~/mcps/bin/<name>-run` wrapper; secrets stay in the MCP `.env`. The
  state store records paths/keys, never values.
- **Permissions = highest-risk adapter**: neutral block is the single
  source; `validate()` asserts the deny-floor survives the round-trip;
  CI checks force-push/credential denials per harness. A harness that
  can't express a deny faithfully emits nothing + marks the cell `gap`
  (OQ3 — never approximate a security deny).
- **Generator deletes nothing** (D7); blast radius bounded to "wrote a
  bad file," caught by validate + atomic write + backup. Keyed-merge
  treats the hand-edited target as possibly-malformed: parse defensively,
  refuse to merge into an unparseable file rather than overwrite it.
- **Merge ownership marking** (OQ1): a self-describing sentinel key
  inside each merged config (`_managed_by_agent_config`) PLUS state.json
  as a fast index — config stays self-explaining if state.json is lost.

### Verify-cells (build-time gates, not assumptions to trust)
Each built behind its `tested_against` pin and confirmed before trusted:
Codex global `AGENTS.md`; opencode/pi reading `~/.agents/skills` (Codex
confirmed it does NOT — the latent bug); Crush subagents/hooks/commands
(matrix marks `gap` until confirmed); pi identity (`@mariozechner/
pi-coding-agent`) — pi adapter built last, most speculative.

## Roadmap                                                 (Phase 9 ran)

Sequencing constraint: the Claude path is in daily use and must not
regress, so Phase 1 proves the whole architecture on Claude before any
other harness is touched. "Hardening" (D6–D8) is cross-cutting, not a
phase: atomic-write/partial-failure/validation are in the Phase-1 core,
per-adapter tests come with each adapter, only the clean-machine CI
capstone defers to Phase 3.

### Phase 1: Core + Claude adapter, proven byte-identical
**DONE 2026-06-17.** Generator built, cut over, tested (8 tests green);
state store + stale report landed. Phase 2 (other adapters) is next.
- [x] `agentconfig/core.py` generator core: manifest dispatch, present-
      adapter gating, partial-failure-continues, per-adapter validate,
      end-of-run summary.
- [x] `render.py` `RenderContext`: atomic write (temp+`os.replace`),
      backup-on-change, skip-if-unchanged, legacy-symlink→copy, `--check`
      dry-run. (This *is* the separate-file strategy.)
- [x] `manifest.py` loader: frozen dataclasses from `manifest.toml`,
      fail-fast validation (missing rule file / skill / claude harness).
- [~] `reconcile.py`: separate-file is the RenderContext; **keyed-merge +
      sentinel-key (OQ1) deferred to Phase 2** (no JSON config to merge
      into until the other adapters exist).
- [x] `state.json` managed-state store (`~/.agent-config/state.json`,
      env-overridable) + stale report (D7 report-only, never deletes).
- [x] Adapter contract (`adapter.py` ABC) + **Claude adapter**: rules
      (generated `CLAUDE.md` + copied rule files), settings, skills,
      subagents, hooks. (Full permissions decomposition is Phase 2.)
- [x] `manifest.toml` authored (rules + preamble + portable skills + claude).
- [x] `install.sh` demoted: Claude config rendered by `python3 -m
      agentconfig`; cross-agent skills + AGENTS.md flatten + MCP clone
      stay bash. Dir vars env-overridable; added `--config-only`.
- [x] **Golden test passed** (generator == legacy bash placement,
      byte-identical) — the one-time cut-over gate. Replaced post-cutover
      with durable tests (`tests/test_claude.py`: source-equality,
      idempotency, RenderContext backup/symlink/dry-run) + `test.sh`.
      Verified idempotent against live `~/.claude` (35 ok, 0 changes).
**Out of scope**: other 4 harnesses, CI container test, the rename.
**Effort**: the bulk of net-new code — done bar the state store.

### Phase 2: Remaining adapters, native-first, one at a time
**In progress 2026-06-17.** Verification done for Codex (below); shared
AGENTS.md renderer + Codex rules adapter landed.
- **Verify-cells confirmed (Codex, current docs 2026-06)**: global
  `~/.codex/AGENTS.md` IS read (standard discovery, not flag-gated — the
  install.sh flatten was correct). Skills register via `[[skills.config]]`
  `path` in `config.toml`; Codex does NOT read `~/.agents/skills` (the
  latent bug). MCP = `[mcp_servers.<id>]`; hooks = `[hooks.<Event>]`
  matcher groups.
- [~] **Codex** adapter — rules, skills, MCP done; hooks = gap; perms TODO.
  - [x] **rules** → `~/.codex/AGENTS.md` (separate file, shared renderer).
  - [x] **skills** → copied to `~/.codex/skills` + `[[skills.config]]`
    paths (the latent-bug fix; Codex doesn't read `~/.agents/skills`).
  - [x] **MCP** → `[mcp_servers.<name>]` from manifest `[mcp.*]` with D4
    per-MCP targeting; command = wrapper, no secrets. Verified live: our
    servers coexist with the user's existing `mcp_servers`.
  - [x] **Infra**: `reconcile.apply_managed_block` (comment-preserving
    TOML managed block — config.toml is co-managed by Codex + hand-edited;
    proven to preserve `model`/`[projects.*]`/existing `mcp_servers`
    byte-for-byte) + `tomlfmt` bounded emit (no arbitrary round-trip).
    D5 refinement: TOML→managed-block, JSON→keyed-merge (later).
  - [ ] **hooks = NAMED GAP (D3 fail-safe).** The Claude hook scripts are
    bound to Claude's hook I/O contract (`.tool_input.*` in,
    `hookSpecificOutput` out); run by Codex they silently no-op. Shipping
    them = false safety signal. Porting needs harness-aware scripts — a
    deliberate separate effort, not "register the hook."
  - [x] **permissions = NAMED GAP** (verified 2026-06, user-confirmed).
    Codex has NO bash-command deny mechanism → the force-push/rm-rf floor
    can't port. File-read denies live only in a `[permissions.<name>]`
    profile activated by the global `default_permissions` key (mutually
    exclusive with `sandbox_mode`) — emitting it would commandeer Codex's
    entire security policy for an incomplete floor. So: gap; rely on
    Codex's native sandbox + approval (OQ3 fail-safe; D3 "full port" is
    structurally impossible here). Opt-in profile generation deferred.
  - **Codex adapter COMPLETE**: rules + skills + MCP ported; hooks +
    permissions are honest, documented gaps.
- [~] **opencode** adapter — rules + MCP + skills done; perms/subagents/
      commands next.
  - **Verified (2026-06)**: `~/.config/opencode/opencode.json` (plain JSON
    /JSONC); reads `~/.agents/skills` **natively** (so skills need no
    adapter work — already exported); permission model is command-pattern
    `allow`/`ask`/`deny` (the "closest to Claude" — bash denies CAN port).
  - [x] **rules** → `~/.config/opencode/AGENTS.md` (shared renderer).
  - [x] **MCP** → `opencode.json` `mcp` via **JSON keyed-merge** (new
    infra: deep-merge, JSONC-comment fail-safe). Verified live: preserves
    `provider.vllm`/`model`/existing `office-*` servers, adds ours.
  - [x] **skills** → native (`~/.agents/skills`); nothing to do.
  - [x] **permissions** — the real win. Bash allow/deny floor ported from
    settings.json to opencode's command-pattern model (`permission.bash`,
    `*`:ask + allows + denies-last). Verified live: all 10 denies + 22
    allows, `provider.vllm` preserved. `Read()` credential denies = partial
    gap (opencode governs bash/edit, not file reads). `permissions.py`
    shared parser.
  - [x] **subagents = GAP** (user-confirmed). The 12 agents are
    infrastructure for Claude-only skills (deep-planner/writing-architect/
    llm-council) that don't run in opencode — definitions with no caller.
    Per-subagent targets = ["claude"]. Avoids a fragile stdlib YAML parser
    for zero working value.
  - **hooks = gap** (same Claude-script-contract issue as Codex).
  - **commands = N/A** (no separate source; skills already reach opencode
    natively via `~/.agents/skills`).
  - **opencode adapter COMPLETE**: rules + skills + MCP + permissions
    ported; subagents/hooks = gaps; commands N/A.
  - opencode AGENTS.md flatten removed from install.sh (now generator);
    the unused `write_flattened_rules` bash function deleted.
- [ ] **Crush** adapter (write the missing `AGENTS.md`; `crush.json`
      mcp + skills_paths + Permissions struct). Verify subagents/hooks.
- [ ] **pi** adapter LAST (verify identity `@mariozechner/pi-coding-agent`
      + paths; Skills, AGENTS.md, MCP-via-extension shim).
- [ ] Per-adapter: unit tests, permissions deny-floor round-trip check,
      `tested_against` pin, `(verify)`-cell confirmation before trusting.
- [ ] MCP auto-registration with per-MCP harness targeting (D4).
- [ ] Generate + publish the support matrix from `[matrix.*]`.
**Out of scope**: the rename; the clean-machine CI capstone.
**Effort**: ~one focused unit per adapter; pi is the wildcard.
**Depends on**: Phase 1 (core + contract).

### Phase 3: Operational capstone + rename + docs
- [ ] Clean-machine smoke test in CI (container → bootstrap → assert
      artifacts placed + parse, across harnesses).
- [ ] GitHub Actions: run `./test.sh` + the smoke test on push.
- [ ] Stale-report polish (the D7 no-delete reporting).
- [ ] Rename `claude-config → agent-config`: repo dir, GitHub repo,
      `install.sh` self-refs, machine bootstrap clones.
- [ ] README/docs rewrite for the harness-neutral reality + embed the
      generated support matrix.
**Out of scope**: nothing — closes the redesign.
**Why last**: rename is cosmetic-with-blast-radius (prove the work
first); the CI capstone needs all adapters to be meaningful.
**Depends on**: Phases 1–2.

## Dependencies & Risks                                    (always)
- **Re-architecture of a working installer**: install.sh works today;
  the redesign must not regress the Claude Code path that's in daily use.
- **Capability matrix has unverified cells** (flagged in the research):
  Codex global AGENTS.md, opencode/pi reading `~/.agents/skills`, Crush
  subagents/hooks/commands, pi identity. Verify before building on them.
- **Over-engineering**: the central risk per calibration. The adapter
  layer must earn each abstraction.
