---
name: doc-sync
description: "Audit a repo's documentation against its code and bring it back in sync. Inventories all docs (README, guides, per-module READMEs, a docs-site), fans out doc-auditor sub-agents to cross-check every concrete claim against the source, returns a tiered report with proving paths, then — on your call — fixes the stale docs (verifying before each edit) and rebuilds any docs site. Trigger on \"check the docs\", \"are my docs current\", \"audit the documentation\", \"docs drift\", or a pre-release doc pass. NOT for answering a question from docs (use doc-grounded) and NOT for prose/writing quality (use the writing reviewers) — this checks whether the docs are factually true against the code."
---

# Doc Sync

Docs drift because code moves and prose doesn't. A feature ships, a module is
renamed, a service is deleted, an env var changes — and the README, the guides,
the per-crate notes, and the docs-site keep describing the old world. This skill
finds that drift by treating every concrete claim in the docs as an assertion
about the code, proving which ones are now false, and (on your say-so) fixing
them and rebuilding the site.

It is the documentation analogue of `code-review-deep`: deterministic inventory,
parallel fan-out of a sharp worker agent (`doc-auditor`), claim-by-claim
verification against the source, a triaged report, and a verified fix pass.

**Two layers.** This skill is the *periodic, semantic* layer — run it before a
release or after a big change. Its cheap, *always-on* counterpart lives in
[`lint/`](lint/): a no-LLM `check-docs.sh` (dead-link check via `lychee` + a
`.docs-lint` denylist of removed tokens) wired into CI, catching the
high-frequency drift on every commit between audits. When you finish a fix pass,
offer to install or update that layer — in particular, add every token you just
removed to the repo's `.docs-lint`, so it can't creep back. (In one run the lint
caught eight dead references the LLM audit had missed — the layers are
complementary, not redundant.)

## When to use this skill

- "Check the docs", "are my docs current", "audit the documentation", "the docs
  have probably drifted"
- After a feature, refactor, rename, or subsystem removal that the docs haven't
  caught up with
- Before a release, so the published docs match what ships
- Inheriting or returning to a repo with many `.md`/docs pages of unknown freshness

This shines on repos with **more than just a README** — user guides, developer
guides, per-module READMEs, example docs, a generated docs-site — where no one
person remembers what every page claims.

## Boundaries

- **vs `doc-grounded`**: that skill *answers a question* from a doc corpus. This
  one *checks the docs against the code* for staleness. Different jobs.
- **vs the writing reviewers** (`developmental-reviewer`, `structural-reviewer`,
  `human-writer`): those judge prose — structure, flow, tone, AI-tells. This
  judges *facts* — is the claim true against the code. A doc can be beautifully
  written and completely wrong; that's this skill's catch.
- **vs `code-review-deep`**: that reviews the code. This reviews what the docs
  *say about* the code. If the audit keeps surfacing that the code itself is a
  mess (not just mis-documented), say so and point at `code-review-deep`.

## Process

Work in order. The discipline is what makes it repeatable instead of "the model
skimmed the README and declared it fine."

### 1 — Inventory

List every doc, not just the obvious ones:

```bash
git ls-files '*.md' '*.markdown' '*.qmd' '*.rst' '*.mdx' '*.adoc' \
  | grep -vE 'node_modules|target/|vendor/|\.venv|third_party'
```

Then detect a **docs-site generator** — `_quarto.yml`, `mkdocs.yml`, `conf.py`
(Sphinx), `book.toml` (mdBook), `docusaurus.config.*`. If present, find its
**source tree vs. rendered output** (e.g. Quarto's `output-dir`). You audit and
fix the *source*; the rendered HTML regenerates. A common miss: the real docs
live in `.qmd`/`.rst` source that a `*.md`-only inventory skips — widen the glob
when a generator is present.

### 2 — Focus

Establish what most likely drifted, so the audit knows where to dig:

- What changed recently? `git log --oneline -20`, recent feature/refactor/rename
  commits, deleted directories or crates.
- The canonical commands/structure: read `CLAUDE.md`, `Makefile`/`justfile`, CI
  config, the workspace/package manifest. These are the truth the docs' commands
  and inventories must match.

Pass this context into the fan-out so auditors check the high-risk claims, not
only generic ones. But the audit is still general — drift isn't limited to the
last change.

### 3 — Audit (fan out `doc-auditor`, in parallel)

Cluster the docs (root/project docs · user guide · developer guide · per-module
READMEs · examples · etc.) and spawn **one `doc-auditor` per cluster in a single
message** so they run concurrently. Give each its file list, the focus context
from step 2, and the instruction to cite a proving code path for every finding
and to verify before reporting. Don't audit a huge repo from one context —
breadth is the whole point of the fan-out.

### 4 — Synthesize

Collect the findings into one report, grouped by severity tier (1 plainly-wrong
/ broken, 2 stale specifics, 3 incomplete), each with the doc location, the
stale claim, the current reality + proving path, and a one-line fix. Note what
was checked and is **clean**, so "accurate" is a verified result, not a gap in
coverage. Surface any cross-cutting theme (one deleted subsystem leaving
fingerprints across five docs is one story, not five nits).

Deliver this report whether or not a fix follows — the audit alone is often the
ask.

### 5 — Decide the fix scope (with the user)

**Do not auto-fix.** Docs are prose; a wrong "fix" is worse than a known-stale
line, and auditors do produce the occasional false positive. Present the tiered
report and let the user choose scope (everything / website-only / tier 1–2 /
just the report). One question, then act.

### 6 — Fix (fan out, verify before each edit)

For the chosen scope, fan out fixers by file cluster (no two touch the same
file, so it's safe in parallel) — or do it inline for a small set. Each fixer:

- **Re-verifies every finding against the code before editing.** The audit
  cited a proving path; confirm it still holds. Auditors mis-call "X doesn't
  exist" when X does — a fixer that blindly applies that deletes correct content.
  (A real run caught exactly this: a "remove the nonexistent `conftest.py`
  reference" finding was wrong — the file existed — and the fixer correctly left
  it.)
- **Edits source only** — never the rendered docs-site output, never code.
- Makes **minimal, surgical** edits that preserve the page's existing voice and
  structure. This is a freshness pass, not a rewrite.
- Reports what it changed per file.

### 7 — Verify

- If there's a docs-site generator, **build it** (`quarto render`,
  `mkdocs build`, `sphinx-build`, `mdbook build`). A clean build confirms the
  edits didn't break the site's syntax; the build log surfaces any broken
  reference. If the rendered output is committed to the repo (e.g. a
  GitHub-Pages `docs/` dir with no render-CI), regenerate and stage it too, or
  the published site stays stale.
- Confirm the diff touched **only docs** — no `.rs`/`.py`/source files, no
  generated output you didn't intend. `git status`/`git diff --stat`.
- Respect the repo's commit conventions (branch policy, files that must stay
  unstaged, trailer). Commit only when asked.

## Principles baked in

- **Proving path or it's not a finding.** Every stale claim points at the code
  that proves it. No path → not reported (or flagged "unverified", separately).
- **Verify before you fix.** The fix pass re-checks the code, because the audit
  is AI-generated and occasionally wrong. This is the difference between a
  freshness pass and a content-destroying one.
- **Source, not rendered.** Edit `.qmd`/`.rst`/`.md` source; let the generator
  rebuild the HTML.
- **Tier, don't dump.** A 60-item flat list reads as noise. Plainly-wrong first,
  incomplete last, cross-cutting themes named.
- **Audit ≠ fix.** The report stands on its own; fixing is a separate, opted-in
  step with its own scope decision.
