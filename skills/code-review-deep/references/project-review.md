# Project Review — whole-codebase assessment

Change review asks "should this merge?" Project review asks a bigger question: **is this codebase worth continuing to build on, and can anyone other than its author work on it?** You're a staff engineer brought in to answer "do we keep investing in this, refactor it, or rebuild it?" The unit of analysis is the architecture, not a diff.

The output is a single verdict, led with, then the evidence:

- **Continue** — sound foundation. Normal change review and incremental improvement apply. Problems are local.
- **Refactor** — the structure has real problems but a salvageable core. Worth a focused, planned restructuring. Name the specific restructurings and their order.
- **Rebuild** — the problems *are* the structure. Incremental fixes can't reach a good state because the foundation is wrong (a God object everything depends on, no tests to refactor against, parallel half-migrated mechanisms). Recommend a rebuild and say what to carry over. This is a real, defensible verdict — don't soften it into "some refactoring needed" when the honest answer is "start over."

Reaching "rebuild" is not failure on the author's part and shouldn't be delivered as one. Recognizing a dead end early is good engineering.

## Use subagents to keep your context clean

A whole codebase does not fit usefully in one context window, and reading every file yourself buries the signal under detail. Fan the legwork out to parallel subagents, each with a **clean context** and a **narrow brief**, each returning a written conclusion with `file:line` evidence — not a file tour. You stay in the orchestrator role and synthesize the verdict from their reports.

A typical split (adapt to the repo's actual shape):

- **Backend / architecture** — package layout, layering, the main request/data flow, God objects, coupling, parallel mechanisms.
- **Frontend / UI + user flow** — how a real user reaches the product, whether the advertised entry point works, UI structure.
- **Repo hygiene & reproducibility** — `git ls-files` composition, tracked artifacts, archive/build bloat, orphaned or nested repos, secrets, and whether a clean clone builds and runs from the documented steps.
- **Tests & quality** — is there a real suite, does it run, does it cover anything load-bearing, or is it manual scripts masquerading as tests.
- **Cross-module contracts & data flow** — trace the state that crosses boundaries: UI/config state synced to a model or render layer, cache/memo keys derived from structs, producer/consumer serialization pairs (GUI export → CLI import, server → client), defaults declared in more than one place. This is where a "sound architecture, localized cleanups only" verdict goes wrong on a large stateful repo: the architecture *is* sound, but individual features are silently inert because a field never made it across a seam, and nothing in the per-file read reveals it. Follow `references/contract-tracing.md` — it's mostly deterministic enumeration, so this agent returns concrete `field X set but never propagated to sync.rs` hits, not impressions.
- **Docs & commit archaeology** — READMEs and design docs vs. reality; read the commit log and any `archive/` for the project's history.

Give each agent the specific questions and the macro-checklist items it owns, and tell it to report a bottom line plus evidence, not a summary of everything it read. Run the deterministic tools yourself or have the owning agent run them and return raw output.

**The judgment is yours, not the subagents'.** Delegate the reading and evidence-gathering; never delegate the verdict. Subagents fan out; you decide.

**Prime them to be skeptical, or they'll come back congratulatory.** A general-purpose subagent pointed at an area tends to praise it ("professional-grade," "well-architected") and miss the duplication and slop. Each area-scanner prompt must forbid praise verdicts, demand `file:line` evidence per claim, tell it to read the enforced house conventions (and exclude vendored/ported code) so it doesn't flag style as rot, and require a position-taking bottom line. Prefer the purpose-built **`code-skeptic`** agent over `general-purpose` for these workers.

**Verify every delegated claim before it enters the report.** Subagents misread line numbers, contradict each other, and confidently report bugs that don't exist. Re-check each high-severity finding against the actual code, discard the false positives explicitly (a sentence each — it shows you caught them), and never ship "an agent said X but I didn't check." If you couldn't verify it, either verify it or cut it. The context you save by fanning out is wasted if unverified noise lands in the verdict.

## The process

1. **Map the territory.** Size (LOC by language and by area), top-level structure, package roots, entry points, how it's built and run, and the path a user takes to the product. One sentence per area: what is this and what does it do.
2. **Establish ground truth with structural facts.** This is the grounding step — the project-review equivalent of running scanners. Don't eyeball; measure. `git ls-files` to see what's *actually tracked* (vs. just present on disk — gitignored artifacts are not findings, so check before flagging). Repo composition by directory. Largest files and classes (God-object candidates). Import/dependency graph and cycles. Duplicate or parallel mechanisms. **Carve out vendored / ported / generated code first** — a faithful port of a reference algorithm (an InChI implementation mirroring the upstream C, a vendored crypto routine) or generated code (parsers, protobufs, `bindgen` output) is *supposed* to be large, repetitive, and stylistically unlike the rest of the repo; flagging it as a God file or AI slop is a false positive that buries the real findings. Identify it via LICENSE/SPDX headers, "ported from"/"generated by" comments, a `vendor/`/`third_party/`/`generated/` convention, or a crate whose docs say "port of X"; exclude those paths from the God-file/AI-slop/duplication metrics, say so explicitly ("the five largest files are all the vendored InChI port, excluded"), and run the smell metrics on the hand-written code only. Run the test suite, the linters, and the type checker — and if they aren't installed, **provision them** (`uvx ruff`, a throwaway venv, `pytest --cov`) before writing "no linter ran." One-off installs are cheap, and a real audit doesn't skip them. When coverage is available, cite the measured number, not an eyeballed estimate.
3. **Read the architecture.** Trace the main flow end to end. Identify the load-bearing structures and ask whether they're sound. This is where you find the things metrics miss: a class named one thing that does another, two systems doing the same job, a missing boundary between layers. For the riskiest runtime logic — LLM/agent orchestration, background jobs, async flows, anything with no test around it — **exercise it rather than reading it**: mock the model or external call, replay a fixture, or run the one path. "Assessed by reading only, no API key" is where a review misses the real bug; if you genuinely can't run it, flag that loudly in the verdict instead of implying you verified it.
4. **Doc and commit archaeology.** Read the READMEs, design docs, and the commit log as evidence. A pile of competing `ARCHITECTURE_*`, `REDESIGN_*`, `AUDIT_*`, `PHASE_N_COMPLETE` documents is itself a finding: it means the design never converged. Repeated churn on the same files across commits is thrash.
5. **Apply the three lenses** (below).
6. **Render the verdict and the salvage list.**

## The three lenses

**Sustainability — can this change safely over time?**
- Are there real tests, and do they cover load-bearing logic? Run coverage and cite the measured number rather than estimating it. (No tests around a God object is a compounding trap.)
- Coupling: is there a single object/module everything depends on? Can any piece be changed or tested in isolation?
- Dependency health: bleeding-edge, abandoned, or unpinned? Lockfile present and honest?
- Bus factor: could anyone but the author make a change without breaking something unseen?

**New-developer onboarding — could someone else pick this up?**
- Clean-clone-to-running: does `git clone` + the documented steps actually produce a running app? (Orphaned/nested repos, env names that don't match the committed config, and missing build steps all break this.)
- Structural legibility: does the layout tell a newcomer where things live, or are there overlapping package roots and misleading names?
- Are the docs current and singular, or is there a graveyard of contradictory ones?
- Honest estimate: hours, days, or weeks to a first safe contribution?

**Typical-user interaction — does the product actually work for a user?**
- Trace the real path from launch to the user-facing surface. Does the advertised entry point (README, launch script) lead somewhere that works?
- Is the core flow coherent, or wired to features that are half-removed or broken?
- Separate the product *concept* (often fine) from *this implementation* of it (often not).

## Macro structural smells

The checklist for project review. Mark each present/absent with evidence.

- [ ] **God object / God file** — one file or class everything routes through (e.g. a 2000+ line "manager" that is the database *and* the search engine *and* the AI client). The single strongest rebuild signal. (Size alone isn't the smell — a large *vendored/ported/generated* file is expected; apply this only to hand-written code, per the carve-out in step 2. A 2000-line file that does one cohesive job is also not a God file; the tell is *unrelated responsibilities* converging.)
- [ ] **Parallel mechanisms** — two task queues, two config loaders, two HTTP clients doing the same job; especially with **misleading names** (a `celery_app.py` that actually runs Huey). Evidence of a migration that never finished.
- [ ] **Multiple package roots / unclear layering** — two top-level source trees with overlapping responsibilities and no clean web/domain boundary.
- [ ] **Test theater** — empty `tests/`, or manual run-once scripts named `test_*` that assert nothing, presented as a suite.
- [ ] **Repo hygiene at scale** — committed binaries, build artifacts, `node_modules`, or an `archive/` that dominates the tracked file count. Orphaned/nested `.git` directories. (Verify tracked vs. ignored first.)
- [ ] **Doc non-convergence** — many competing architecture/redesign/audit docs instead of one current one.
- [ ] **Commit thrash** — repeated churn and reverts on the same files; "Phase N Complete" doc-driven flailing.
- [ ] **Dependency risk** — abandoned or bleeding-edge deps; no lockfile.
- [ ] **Dead code / abandoned features in-tree** — kept in `archive/` or commented out rather than in git history.
- [ ] **Not reproducible** — can't build/run from a clean clone with the documented steps.

## Rendering the verdict

Lead with Continue / Refactor / Rebuild and a one-paragraph justification. Then the load-bearing reasons — grouped, top few, not an exhaustive dump. Then the three lenses. Then the salvage list.

**Anti-pile-on, hard rule for bad code:** when the verdict is Rebuild, line-level nits and style findings are noise — say so explicitly and suppress them. Listing 200 formatting issues on code you're recommending be deleted wastes everyone's time and buries the real message. The finding *is* the architecture.

## Salvage list

When the verdict is Refactor or Rebuild, separate the architecture (discard) from the domain knowledge (keep). Be specific: name the modules that encode hard-won, expensive-to-rederive logic worth lifting into the new design, and name what to drop. This is the most actionable thing you give the author.

## Report format

- **Verdict** — Continue / Refactor / Rebuild + one-paragraph summary.
- **Why this verdict** — the load-bearing structural problems, grouped, top few, each with evidence (`file:line`, counts, `git` facts).
- **The three lenses** — sustainability, new-developer onboarding, typical-user interaction.
- **What's worth keeping** — the salvage list.
- **Praise** — honest. The product concept, good module decomposition, a modern stack choice, or the author's own good call to stop. Don't manufacture it; don't skip it.
- **What was NOT assessed** — be honest about coverage (tools that wouldn't run, areas skipped, runtime behavior not exercised).

Length follows the verdict. A "Continue" can be short. A "Rebuild" needs enough evidence that the author trusts the call.
