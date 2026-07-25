---
name: bug-scan
description: "Proactive hunt for latent bugs nobody reported: inventory prior coverage, partition by failure mode, fan out code-skeptic workers, then verify and rank what returns. Trigger on 'hunt for bugs', 'scan for latent defects', 'find what's silently wrong', or 'adversarial sweep'. NOT for a known bug (bug-hunter), a health verdict (code-review-deep), or exploitability (security-review-deep)."
---

# Bug Scan

`bug-hunter` starts from a reported bug. This skill starts from none: it is
the proactive sweep that finds the defects surviving your test suite and
your review passes, because nobody has gone looking. The worker is the
`code-skeptic` agent, which is sharp; what it lacks alone is a conductor.
This skill is the conductor: coverage bookkeeping, partition, briefs,
verification, ranking.

The recipe was distilled from a session where five workers on a 22-crate
workspace found, among others: a parser silently discarding 8–20% of atoms
in every protein/DNA file (the tests asserted `!atoms.is_empty()`), a
converter with two independent bugs in one function, and a relaxation
parser reporting 311 optimization steps for a 20-step run. All had survived
the tests and multiple review passes. The orchestration below is what
caught them; that orchestration is the content of this skill.

## Boundaries

- **vs `bug-hunter`**: that skill root-causes a *known* bug (reported,
  reproduced, or a failing test). This one finds bugs nobody reported.
- **vs `code-review-deep`**: that renders a health verdict
  (Continue/Refactor/Rebuild) or reviews a named change. This one is an
  adversarial hunt for latent correctness defects; it produces a findings
  doc, not a verdict. If a review said "healthy" and the user wants to know
  what it *missed*, that is this skill. Conversely, if the scan keeps
  surfacing structural rot rather than discrete bugs, say so and point at
  `code-review-deep`.
- **vs `security-review-deep`**: exploitability. A correctness bug that is
  also exploitable gets named here and handed there.

## Process

Work in order. The discipline is what makes this repeatable instead of five
agents reading the same three files.

### 0 — Require a scope, and scale to it

Refuse "scan my codebase" with no partition. On a large repo an unscoped
scan degenerates into every worker reading the same entry points. Get a
scope: the whole workspace (fine up to ~20 crates/packages), a named set of
crates, or one subsystem. Scale worker count to the scope: ~3 workers for a
small repo, 5 was right for a 22-crate workspace, and past ~7 the reports
start colliding.

### 1 — Coverage inventory, then the ALREADY-REVIEWED list

Before spawning anything, establish what is already covered: skim the test
suite's assertion shapes, prior review findings, and any findings docs in
the project's notes dir. Build an explicit **ALREADY REVIEWED — do not
re-report** list and pass it into every worker brief. Without it, workers
independently re-derive the same known findings and the reports collide.

The list is explicit or it doesn't exist. If the user points at a prior
findings doc, use it. If the project has a notes dir, you may glob it and
*propose* entries to the user for confirmation; never auto-apply, because
silent under-scanning is worse than the friction of asking. On a re-run
after a review pass, ask what the prior pass covered before spending a
single worker.

Keep the worker input compact. Collapse prior reports into a coverage ledger
of at most 20 short bullets: finding ID, affected area, and enough detail to
recognize overlap. If that will not fit, write
`notes/bug-scan-<date>-coverage.md` and give workers that path; they read the
ledger, not every raw historical report. This keeps duplicated prompt payload
out of five contexts without weakening the exclusion list.

### 2 — Partition by failure mode, not by directory

Directory splits overlap badly (two workers flag the same parser from
different sides); failure-mode splits don't. Assign each worker one lens:

- **Panic-safety** — the paths that crash: unwraps, unchecked slices,
  "unreachable" code that is reachable, allocation bombs.
- **Domain/format parsers** — split into 2+ workers by subject matter when
  the repo has several (e.g. structure formats vs. QC output formats).
  Parsers are where silently-wrong lives.
- **Concurrency** — shared mutable state, background jobs, ordering
  assumptions, stale caches.
- **Silent failure** — swallowed errors, `.ok()`,
  `unwrap_or_default`/`or None` on real values, errors logged and dropped.

Adapt the set to the repo, but keep the rule: one failure mode per worker,
non-overlapping by construction.

### 3 — Brief every worker with the impact classifier

Use the named `code-skeptic` worker wherever the harness provides it:
Claude, Codex, and OpenCode. On a harness with no worker fan-out, run two
sequential, non-overlapping failure-mode passes yourself and label the result
**reduced coverage**; do not pretend it had independent reviewers.

Launch all workers in one message when the combined briefs fit the harness.
If the handoff is too large or a launch fails, preserve the partitions and
launch batches of three, then the remainder. Never retry the same oversized
fan-out verbatim.

Every brief carries the scope, its failure-mode lens, the compact
ALREADY-REVIEWED ledger, and the classifier below. The classifier did more
for signal quality than anything else in the original session: a worker told
to discard the benign class returns 6 real findings instead of a padded list
of 50.

```
You are hunting latent defects in <scope>. Your lens: <failure mode>.
Assume bugs exist; your job is to find them, not to reassure.

ALREADY REVIEWED — do not re-report:
- <known findings / areas from step 1>

Classify every candidate by what the user actually sees:
(A) benign — invisible, no consequence. DISCARD entirely; do not report.
(B) cosmetic — visible but harmless. Report only if trivial to fix.
(C) silently wrong — output the user would trust but shouldn't. The prize.

I would rather have 5 real (C) findings than 50 mixed ones.

Return at most 3 confirmed findings. Put at most 2 lower-confidence candidates
under "couldn't confirm"; discard everything else after recording it only in
your own reasoning.

Every finding needs:
- file:line and a quote of the offending code
- a concrete trigger: the input or call path that makes it fire
- blast radius: what the user sees (wrong number? crash? stale render?)
- a confidence mark — "unverified" if you cannot confirm reachability
  from the code. Honest unverified beats confident wrong.
```

### 4 — Verify before you report

Workers misread, over-flag, and get numbers wrong. Before any finding
enters the report:

- **Re-derive every load-bearing number yourself.** In the original
  session a worker reported 19 ionic steps; a two-second `grep -c` showed
  20. The bug was real either way, but an unverified number makes the
  report unusable. Counts, percentages, line numbers: re-run the count,
  re-read the lines.
- Discard false positives explicitly, one sentence each. It shows the
  survivors were checked.
- Keep workers' "unverified" flags unless you verified them yourself.
  Flagged findings go in their own section, not the main list.

### 5 — Rank across all workers, then write it down

Merge every worker's findings and rank by what the user can detect, not by
crash-vs-no-crash:

1. **Silently wrong output** — the worst class for a correctness tool: the
   user trusts a wrong number.
2. **Crashes** — loud, but they lose work.
3. **Wrong but visible** — the user can tell something broke.
4. **Structural** — bug-shaped code that hasn't fired yet.

Write the deliverable to the project's notes dir (or `~/scratch/` if it has
none): a findings doc plus one consolidated ranked list. In chat, give a
short spoken summary: the top findings, what was scanned, what was
explicitly not covered. Not a wall of text; the doc is the wall.

## Principles baked in

- **Coverage bookkeeping first.** A scan that re-finds known bugs teaches
  nothing and burns the user's patience triaging duplicates.
- **Failure modes, not directories.** Overlap is the enemy; partition by
  how things break.
- **Discard benign at the worker.** Filtering upstream keeps both the
  report and the main context clean.
- **file:line + trigger + blast radius, or it isn't a finding.**
- **The conductor owns the numbers.** Workers propose; the conductor
  verifies before the user ever sees a figure.
- **Severity = can the user tell.** Silently wrong outranks crash.
