---
name: overnight-audit
description: "Unattended, long-running inspection that generates candidate defects mechanically and verifies them before reporting. Trigger on 'overnight audit', 'run an audit while I sleep', 'automate finding what we keep missing', or 'nightly inspection'. NOT an interactive hunt (bug-scan), a known bug (bug-hunter), or a health verdict (code-review-deep)."
---

# Overnight Audit

`bug-scan` sends readers into the code to look for defects. This skill starts
somewhere else: **probes generate candidates mechanically, and the model's only
job is to verify them.** That inversion is the whole point. Unattended, an LLM
asked to "find bugs" returns plausible-sounding non-findings at a rate that
costs more to triage than the exercise saves; a probe that reports "this field
is null in all 237 records" is either true or false and can be checked.

The recipe comes from a session on a 23-crate scientific workspace where a
1739-test suite was green through every real bug found that day. What found
them, in order of yield:

| How | Found |
| --- | --- |
| Mechanical corpus sweep (field empty in *every* record) | 3 |
| A golden diff produced as a side effect of an unrelated bump | 1, the worst |
| Same input two ways (two code paths, two processes, two builds, two libraries) | 5 |
| Deliberately breaking code to see whether a test fails | 4 vacuous tests |
| Reading a note against the code it describes | 1 (a stale blocker) |
| The test suite | 0 |

Every one of those is automatable. None of them is "read this file and think
hard about it".

## Boundaries

- **vs `bug-scan`**: that is interactive, scoped, and reasons about code. This
  is unattended, whole-repo, and reasons only about probe output. When a probe
  candidate needs real investigation, hand it to `bug-scan` rather than
  widening this.
- **vs `differential-test`**: that builds one durable harness against one
  external reference. This runs many probes and reports; it *uses* such a
  harness when the project already has one.
- **vs `code-review-deep`**: no verdict, no architecture opinion.
- **vs `doc-sync`**: overlaps on doc-vs-code staleness. If that is the whole
  ask, use `doc-sync` — its `doc-auditor` is sharper. This skill runs a thin
  version of it because a stale note blocked a feature for weeks in the session
  above.

## Before anything: the tools beat the agents

Do not write an agent for work a tool already does better, cheaper, and without
tokens. Check for and prefer, in this order:

1. **Mutation testing** (`cargo-mutants`, `mutmut`, `stryker`). This directly
   answers "would a test notice if this were wrong", which is the recurring
   failure mode. It needs no model at all and is the ideal overnight job. On the
   workspace above, one small file returned 18 missed mutants of 36 — including
   an arithmetic operator inside the metric the whole depiction subsystem is
   judged on.
2. **Property/round-trip tests** (`proptest`, `hypothesis`) where the project
   serialises anything: export → import → compare is a property, not a test case.
3. **Fuzzing** (`cargo-fuzz`, `atheris`) where the project parses untrusted or
   semi-structured input.

Say plainly if the highest-value next step is "install cargo-mutants and run it
nightly" and this skill is not needed yet. That is a good outcome.

## Process

### 0 — Establish the budget and the machine

Ask, or infer from the request: how long, on what machine, and how many tokens.
These change the design, not just the scale.

**Warn about the build-artifact trap.** Mutation testing is thousands of builds.
On the workspace above, `target/debug/deps` accumulating past ~50k files was the
documented cause of five WindowServer watchdog kills — each one restarting the
GUI session and taking every terminal with it. Any unattended build loop needs a
periodic clean and a capped job count, or it should run on a machine with no GUI
session to lose. Check the project's own build notes for the equivalent trap
before scheduling anything.

### 1 — Inventory the probes the project already has

Most projects have some. Look for `#[ignore]`d diagnostics, `report_*` test
functions, golden fingerprints, parity harnesses, corpus sweeps. These are
probes someone already wrote and stopped running. Listing them is often the
single most valuable step: the session above had a field sweep and a per-fixture
quality sweep sitting unused, and both found real bugs the first night they ran.

### 2 — Run the probe families

Each is deterministic and needs no model. Skip any that do not apply; do not
invent findings to fill a family.

- **Structural anomaly over a corpus.** Serialise every record the project
  produces and report each field that is null, empty, zero, or *identical* in
  every record. An asymmetry — one field empty in all records while its sibling
  is populated in all of them — has no physical cause. Also: declared-but-never-
  written fields, and capabilities/flags that can never be true.
- **Same input, two ways.** Any two paths that should agree: streaming vs
  batch, cached vs cold, two API entry points, two processes (a layout that
  drew differently every launch was found this way), two builds (diff per item,
  never in aggregate), an external library.
- **Invariants the domain guarantees.** Components summing to their total,
  counts a format declares about itself, conservation laws, signs that cannot
  flip. A correlation energy is negative; the bug that reported `+1.2` had been
  pinned by a golden for weeks.
- **Determinism.** Run the same computation in two fresh *processes* and
  compare byte for byte. In-process repetition proves nothing — a hash seed is
  fixed within a process, so the output looks perfectly stable.
- **Vacuous-test detection.** Mutation testing if available. Otherwise, the
  cheap approximation: find tests whose assertions are existence-shaped
  (`is_ok`, `!is_empty`, `> 0`) or that return early when a fixture is missing.
- **Doc claims vs code.** Every concrete claim in a README, plan doc, or code
  comment is an assertion about the system. Check the ones that name a symbol,
  path, flag, or number.

### 3 — Verify every candidate before it reaches the report

This is where the model earns its place, and the rule is absolute:

> A probe hit is a lead to check against the source, not a defect.

For each candidate, one verification agent, with a brief that demands:

- the **source evidence** — file:line, and the code path that produces the
  behaviour;
- a **reproducing command** the reader can paste;
- **expected vs actual as values**, not adjectives.

Drop anything that fails to produce all three. A dropped candidate costs
nothing; a confident wrong finding costs the reader's trust in the whole report,
and after two of those nobody reads the next one.

Verifiers must be able to return "not a defect" and be *rewarded* for it. In the
session above, five of the first ten sweep hits were honest nulls — a field the
CLI stamps later, a quantity the format never prints — and recording *why* they
were honest is what stopped them being re-investigated the following week.

### 4 — The report

One file, in the project's notes directory, dated. Structure:

1. **What ran**, including probes that found nothing — a family with zero hits
   is information, and its absence next time is a regression in coverage.
2. **Confirmed**, ranked by consequence, each with evidence, repro, and the
   values. Consequence means user-visible wrongness, not how surprising it is.
3. **Dismissed, and why.** Equal billing. This is the section that compounds.
4. **Could not verify** — candidates that neither confirmed nor cleared, with
   what was missing. Never promote these to findings.

Close with the honest coverage statement: what was *not* looked at. A report
that reads as exhaustive when it sampled one crate is worse than no report.

## Model choice

Split it. The probes are deterministic and want no model at all; verification
wants judgement and is where a cheap or local model degrades badly — its failure
mode is agreeing that a plausible candidate is real, which is exactly the
failure this design exists to prevent.

If cost forces one model, spend it on verification and cut the number of probe
families instead. A short report that is entirely true is worth more than a long
one that has to be re-checked, because the second one gets re-checked by a human
at a worse hourly rate.
