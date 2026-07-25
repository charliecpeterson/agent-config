# Proposed additions: proactive code scanning, differential testing, env triage

Status: **A-D implemented 2026-07-24.** `differential_check.py` ran against
the real Orbitron corpus with ASE, detected the known PDB defect in all five
bundled files, and now records tool-refused files as disagreements. The
portable `differential-test` skill was derived from that successful run.
Written 2026-07-24 from evidence produced during a long Orbitron session.
Items tagged P0 (clear gap, strong evidence), P1 (good win), P2 (cheap polish).

Everything here is grounded in one session where an ad-hoc multi-agent scan
found a bug that had survived the existing test suite, a nine-part manual
review, and prior review passes. The point of writing it down is that the
*orchestration* is what worked, and it currently lives nowhere.

Source material (Orbitron repo, `~/projects/orbitron/notes/`):
`scan-findings-2026-07-24.md`, `optimization-review-2026-07-24.md`,
`strategy-2026-07-24.md`, `regression-test-drafts.md`, and the drafted harness
`~/projects/orbitron/scripts/differential_check.py`.

---

## A. `bug-scan` skill — proactive multi-agent bug hunt  **[P0]**

### Why this is a gap

| existing | covers | doesn't cover |
|---|---|---|
| `bug-hunter` | a **known** bug — reproduce, root-cause, fix | finding bugs nobody reported |
| `code-review-deep` | whole-codebase health, Continue/Refactor/Rebuild verdict | adversarial hunt for latent defects |
| `security-review-deep` | exploitability | correctness bugs |
| `code-skeptic` (agent) | one area, when *someone else* orchestrates it | the orchestration itself |

`code-skeptic` is the worker and it's good. What's missing is the conductor.

### Evidence it works

Five `code-skeptic` agents, non-overlapping scopes, one session. Found:

- A PDB parser silently discarding **8–20% of atoms in every protein/DNA file**
  (every β-carbon, every phosphate oxygen). Verified by hand afterwards: 79/660
  atoms in 1UBQ, 2/10 in the project's own test fixture. It had survived the
  existing tests because they asserted `!atoms.is_empty()`.
- A basis-set converter with **two** independent bugs in one function — silent
  coefficient misalignment *and* an unchecked-slice panic in the GUI redraw path.
- A QE parser reporting **311 optimization steps for a 20-step relaxation**, and
  an initial energy off by ~770 kcal/mol, both rendered straight to the user.

### The orchestration recipe (this is the actual content of the skill)

1. **Establish what's already covered first.** Do a quick inventory pass, then
   pass an explicit "ALREADY REVIEWED — do not re-report" list into every agent
   brief. Without it, agents re-derive the same findings and the reports collide.
2. **Partition by *failure mode*, not by directory.** What worked:
   - panic-safety (things that crash)
   - domain/format parsers, split into 2+ groups by subject matter
   - concurrency / shared mutable state / background jobs
   - silent failure — swallowed errors, `.ok()`, `unwrap_or_default` on real values
   Directory-based splits overlap badly; failure-mode splits don't.
3. **Give each agent a "what does the user actually see?" classifier** and tell
   it to *discard* the benign class entirely. The silent-failure brief said:
   classify as (A) benign — skip entirely, (B) cosmetic, (C) silently wrong;
   "I would rather have 5 real (C) findings than 50 mixed ones." It returned 6
   real findings instead of a padded list. **This instruction did more for signal
   quality than anything else.**
4. **Require file:line + a concrete trigger + blast radius** for every finding.
5. **Require confidence marking.** "Say unverified if you can't confirm
   reachability." Several came back honestly flagged, which is precisely what
   made the unflagged ones trustworthy.
6. **The conductor verifies load-bearing numbers before reporting them.** In this
   session a scan reported 19 ionic steps; a two-second `grep -c` showed 20. The
   bug was real either way, but unverified numbers make a report unusable.
7. **Rank across all agents at the end**, into: silently-wrong-output → crashes →
   wrong-but-visible → structural. Severity for a *correctness* tool is about
   whether the user can tell something went wrong, not about crash-vs-no-crash.

### Notes for whoever implements it

- **Portable after the 2026-07 harness check.** Claude, Codex, and opencode
  support worker fan-out and receive `code-skeptic` in native formats; pi uses
  the skill's reduced-coverage sequential fallback. Add to `[skills] portable`.
- Should refuse to run without a scope; "scan my codebase" on a 500k-line repo
  with no partition is how you get five agents reading the same three files.
- Scale the agent count to the repo. Five was right for a 22-crate workspace.
- Worth a `--already-covered` style argument so a second run after a review pass
  doesn't repeat it.
- Output shape that worked: findings doc + a consolidated ranked list, written to
  the project's notes dir, plus a short spoken summary. Not a wall of text in chat.

---

## B. `differential-test` skill — validate against reference implementations  **[P1]**

### Why

The deepest finding of the session wasn't a bug, it was a test-suite property:
**the tests asserted that something happened, not that the right thing happened.**

```
tests/pdb.rs      assert!(!atoms.is_empty())        ← passed while dropping 20% of atoms
tests/qe/relax.rs assert!(step_count >= frames)     ← passed at 311 when the answer was 20
inchi golden      141 molecules                     ← guarding 52,637 lines
```

For scientific/numeric code there's a fix most projects can't reach for:
independent implementations of the same domain already exist. For comp-chem
that's `cclib` (QC output), `ASE`/`OpenBabel` (structures), the IUPAC InChI
binary. Parse a corpus with both, diff the quantities that matter.

A working draft exists: `~/projects/orbitron/scripts/differential_check.py`
(compiles, `--help` works, degrades cleanly when no reference lib is installed;
never executed against the real binary). Generalise from it.

### What the skill should do

1. Identify the domain and propose reference implementations for it.
2. Find or build the machine-readable output path from the tool under test
   (Orbitron already had `info --json` with an `atoms` count and an `elements`
   histogram — that histogram alone catches both "atoms dropped" and "wrong
   element assigned").
3. Generate the harness: per-format routing, tolerance handling, and **three**
   distinct outcomes — agree / disagree / *tool refused a file the reference
   read*. That third one is a finding, not a skip.
4. Make every reference backend optional, so a missing library degrades with a
   message instead of failing the run.
5. Exit non-zero on disagreement so it can gate CI once trusted.

Portable (pure Python + prompt, no sub-agents) → add to `[skills] portable`.

---

## C. `env-triage` skill — "is it my code, my build, or my machine?"  **[P1]**

### Why

This session lost well over an hour to a machine problem misdiagnosed twice as a
code problem. The sequence: a build appeared to hang → blamed `nice` (wrong, but
a real finding) → blamed `conda run` output buffering (wrong) → the actual cause
was **every freshly-built binary hanging in `dyld`**, waiting on a synchronous
image-load notification that never came, after a WindowServer watchdog kill left
system daemons wedged. DNS was down too. The fix was a reboot.

Each wrong theory cost a 20–30 minute build cycle to disprove.

### The checklist that would have short-circuited it

- **CPU time vs elapsed.** `ps -o time=,etime=` — this one ratio exposed both the
  QoS throttle (10s CPU / 15min elapsed) and the dyld hang (0.00s CPU, minutes
  elapsed). A process with ~zero CPU is *blocked*, not slow. Check it first.
- **Process state.** Sleeping with 0.00s CPU means blocked before `main()` —
  suspect the loader/OS, not your code.
- **`sample <pid>` before theorising.** The dyld stack named the cause outright.
- **Reproduce outside the toolchain.** Running one freshly-built binary directly
  — no cargo, no conda — proved it was system-wide in seconds.
- **Check system health before blaming the build**: core daemons loaded, any
  daemon spinning at high CPU, DNS resolving, disk space.
- **Know the platform's traps.** On Apple Silicon `nice` demotes to background
  QoS and pins to E-cores — measured **1% duty cycle on a 67%-idle machine**.

Generalises directly to "why is my Slurm job wedged", which is adjacent to but
distinct from `stampede3-debug` (that one is Slurm-specific and assumes the job
is the problem).

Portable → add to `[skills] portable`.

---

## D. Cheap config updates  **[P0 — do these first, they're minutes]**

- [x] **`machines.md`, mac-studio section** — record:
  - Never `nice` a build on Apple Silicon (background QoS → E-cores → ~1% duty
    cycle even on an idle machine). Cap `CARGO_BUILD_JOBS` instead.
  - `conda run` buffers subprocess output; long/parallel builds need
    `--no-capture-output` or they look hung.
  - A full-workspace Rust build once pinned all 24 cores long enough for macOS to
    watchdog-kill WindowServer and restart the GUI session, killing every terminal.
- [x] **`agents/code-skeptic.md`** — add a standing line that numeric claims must
  be labelled verified or unverified, and that the *orchestrator* is expected to
  re-derive load-bearing numbers. (Evidence: 19-vs-20 above.)
- [x] **`style.md`** (landed there instead of `engineering.md`; it's a code-level rule) — a line on test assertions: prefer pinning
  the expected value over asserting existence; `!is_empty()` and `>=` are the two
  shapes that let real regressions through.

---

## Suggested order

1. **D** — minutes, and it stops known-bad advice being repeated.
2. **A** — highest value, most evidence, least overlap with existing skills.
3. **C** — small, and it pays for itself the first time a machine misbehaves.
4. **B** — most work; wants a real project to develop against. Orbitron is the
   obvious candidate since the draft harness and a known-buggy corpus both exist.

## Open questions for the implementer

- Should **A** subsume the "already reviewed" bookkeeping automatically by reading
  a project's notes dir, or stay explicit? Explicit was reliable; automatic would
  be less friction but could silently under-scan.
- Does **B** belong as its own skill, or as a mode of `code-review-deep`? It's
  argued as standalone here because its output is a persistent harness in the
  repo, not a report — a different deliverable shape.
- **A** and `code-review-deep` will overlap at the edges. Worth deciding whether
  `code-review-deep` should end by *suggesting* a `bug-scan`, the way
  `security-review-deep` and the writing skills chain today.
