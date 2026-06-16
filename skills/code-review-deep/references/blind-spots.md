# Blind Spots — bug classes this reviewer has missed before

Read this file at the start of every review. Each entry is a class of bug that
a past review rendered "clean" on and that turned out to be real — found later
by running the code, by a sharper audit, or in production. The point is simple:
a generic reviewer repeats its blind spots; a tuned one doesn't. This file is
what makes *this* reviewer better than a stock rubric, because it's calibrated to
the bugs that actually got shipped here.

The field converged on this pattern — version-controlled review-memory files
(Kilo's `REVIEWS.md`, Greptile's learned rules, Gemini's review memory). This is
the solo, no-RAG version: a flat list, read at the top of a review, appended to
by hand. Keep it that way. A RAG layer here is maintenance you'll regret for a
one-reader tool.

## How to use it

- **At review start:** skim the entries. For each one whose trigger matches the
  code in front of you, run the named check. These are not optional nits — they
  are the checks that *would have caught a real bug* and didn't get run.
- **After a miss:** when a review (yours or a past one) is found to have missed
  something — you ran the app and a bug surfaced, a later audit caught it, it
  broke in use — add an entry. One miss, one entry. This is the only way the
  list earns its keep.
- **Keep it short and specific.** Each entry: the class, the trigger (when it
  applies), the check that catches it, and the real instance it came from. If an
  entry stops being a real risk (the codebase moved on, a lint rule now covers
  it), delete it. A stale blind-spot list is noise.

## Entry format

```
### <short class name>
- **Trigger:** when does this risk apply (so you know whether to run the check)
- **Check:** the concrete thing to run/look at
- **Caught by:** how the real instance was actually found (the method that worked)
- **Instance:** the real bug, with repo + file if useful
```

---

## Entries

### Cross-module state that never crosses the seam
- **Trigger:** a struct/config whose fields are hand-synced, serialized, cached,
  or consumed in a *different* file (UI state → sync → render; export → import;
  struct → cache key).
- **Check:** the contract-trace pass — enumerate every member at each site and
  grep each downstream; a field with zero downstream hits is an inert feature.
  See `contract-tracing.md`. Then run the app and confirm the control/field
  actually does something.
- **Caught by:** running the app after a fix and seeing the change *not* happen
  on screen — not by reading. A static audit also missed two of these.
- **Instance:** Orbitron — inert cartoon checkboxes (`sync.rs` never copied two
  fields), a `RenderCacheKey` missing two fields (toggles hit stale cache), a
  `bootstrap.rs` hardcode silently overriding the view-state default, a CLI that
  ignored most of the GUI's exported preset. A deep review rendered "sound
  architecture, localized cleanups only" and missed all of them.

### UI/UX defaults and wiring that only show up on screen
- **Trigger:** any change to UI defaults, toolbar/menu labels, or what the first
  screen shows.
- **Check:** launch the app and look — does the default actually apply, does the
  control do what its label says, is the first screen what a new user should
  see. Reading the diff does not catch these.
- **Caught by:** running the app during the review (not after shipping).
- **Instance:** Orbitron — labels-on by default (cluttered first screen),
  app launching into edit mode on an empty scene, a "Render" toolbar button that
  actually switched representation style.

### Silent numeric / unit / constant drift
- **Trigger:** any change to math-heavy or scientific code — a refactor, a
  "cleanup," a unit conversion, a constant moved or retyped.
- **Check:** confirm a test pins the actual numeric *value* against a known
  reference, not just shape or "it runs." On a refactor, run the moves-only
  line-set diff with extra scrutiny on numeric literals, formulas, and
  integer-vs-float division.
- **Caught by:** a regression test asserting the real number; eyeballing misses
  a one-character operator or a swapped constant inside a large "move."
- **Instance:** the class that motivates the moves-only check — a constant flip
  or unit swap that every existing test still passes because none assert the
  value.

### Platform / path / env assumptions (dev machine vs. deploy target)
- **Trigger:** filesystem paths, env-var reads, locale/encoding, temp-dir use, or
  anything that runs on both macOS (dev) and Linux/HPC (deploy).
- **Check:** grep for absolute paths and `os.environ` / `env::var` / `$HOME`
  reads; check case-sensitivity assumptions (macOS is case-insensitive, Linux
  isn't), `$HOME` quota vs `$SCRATCH` on clusters, and hardcoded separators.
- **Caught by:** running the path on the other platform or in a clean container —
  not by tests that only ran on the dev Mac.
- **Instance:** general — code green on the dev machine, broken on the cluster.

### Races that pass CI
- **Trigger:** goroutines/threads/async tasks, shared mutable state, channels,
  locks — anything concurrent.
- **Check:** run the race detector (`go test -race`, `cargo miri` / `loom`,
  TSan), or stress/repeat the path under contention.
- **Caught by:** the race detector or load — never the normal suite, which is
  deterministic so the bad interleaving never schedules.
- **Instance:** general — green CI, intermittent failure under real load.

### Resource leaks in long-lived processes
- **Trigger:** anything daemon-shaped or long-running — MCP servers, background
  jobs, long HPC runs, GPU workloads.
- **Check:** run the long-lived path and watch fd count / RSS / `nvidia-smi`
  over time; look for handles, sockets, subprocesses, or caches that open but
  never close or bound.
- **Caught by:** observing growth over time — a short unit test exits before the
  leak matters.
- **Instance:** general — fd/socket leak, VRAM not freed, zombie subprocess,
  unbounded cache.

### Silent truncation / unacknowledged caps
- **Trigger:** a query/API with a row or page limit, a `head`/`take`/`LIMIT`, a
  batch size, pagination.
- **Check:** for every limit, ask whether the caller assumes it got *everything*;
  test with input larger than the cap.
- **Caught by:** testing past the cap — the happy path with small data hides it,
  and the code silently drops the rest at scale.
- **Instance:** general — reads page one and treats it as the whole set; a query
  capped at N rows consumed as complete.

### Nondeterminism / irreproducibility (ML and data)
- **Trigger:** anything with randomness, GPU compute, or order-dependent output —
  training, sampling, dict/set iteration leaking into results, `os.walk` order.
- **Check:** run it twice and diff the output; grep for RNG use without a seed.
- **Caught by:** the run-twice-and-diff — a single test run passes and hides the
  irreproducibility.
- **Instance:** general — results don't reproduce because a seed was unset or
  iteration order leaked downstream.

### Errors swallowed that fail *open*
- **Trigger:** a `try/except` or `catch` around validation, auth, bounds, or any
  check whose failure should *stop* the operation.
- **Check:** trace what state the caller proceeds with *after* the swallowed
  error — does it run on bad/empty/default data as if nothing failed?
- **Caught by:** following the post-error control flow, not checking whether the
  error was logged. (Overlaps `security-review-deep` — flag and defer there for
  depth.)
- **Instance:** general — a caught exception hides a failed check and execution
  continues in an unsafe state.

### Tests that look green but didn't run
- **Trigger:** any tests step where coverage/pass looks fine.
- **Check:** confirm the test *count actually ran and assertions fired* — not
  just that the file exists. Watch for tests skipped by a missing marker, an
  import error swallowed into a skip, or an `xfail` that silently passes.
- **Caught by:** reading the runner's collected/ran/skipped counts, not the
  green checkmark.
- **Instance:** general — coverage looks fine, but the test never executed.
