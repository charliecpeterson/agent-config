# Code Review Checklist

Walk this for every changed file. For each item, mark ✅ / ⚠️ / N/A with a one-line reason. "N/A: this change touches no public API" is a real review artifact — silence isn't.

Categories are in priority order. The first five carry most of the value; don't let the long tail crowd them out.

---

## 1. Correctness & logic

The review's first job: does the code do what it claims, on every path?

- [ ] Off-by-one and boundary conditions (empty collection, single element, first/last, max value)
- [ ] Null / None / undefined handled where it can actually occur
- [ ] Every branch reachable and correct; no inverted conditions, no dead branches
- [ ] Error and failure paths return/raise correctly, not just the happy path
- [ ] Async/await ordering: nothing awaited too late, no fire-and-forget that should be awaited
- [ ] Transaction boundaries: the right operations commit/rollback together
- [ ] No convoluted control flow that should be flat — deeply nested conditionals, flag variables threading through, early-return logic written as a pyramid
- [ ] Arithmetic: integer division, float rounding, units, overflow where it matters
- [ ] The change actually solves the stated problem (re-read the PR description / issue against the code)

## 2. Tests

Covered in depth at Step 4 of the process. Record the verdict here.

- [ ] New code has new tests
- [ ] Tests call the changed code path (not just import the module)
- [ ] The trickiest line is covered — special-case guards, fallback branches, boundary conditions, anything with a "this is subtle" comment (see Step 4)
- [ ] No trivially-passing tests (`assert True`, no assertions, asserting on a mock's configured return)
- [ ] Changed tests reflect real behavior change, not weakened assertions
- [ ] Happy path paired with at least one negative / error-path test
- [ ] Edge cases from category 1 have a test each, where practical
- [ ] For the fragile bit, the suite actually *catches* a regression, not just covers the line — mutation-test it (`cargo mutants` / `mutmut` / `stryker`) on load-bearing logic (parsers, math, guards, state machines). A surviving mutant is a real hole; the fix is to write the test that kills it. See Step 4.

## 3. Code flow & coherence

Does the change fit the codebase, or was it bolted on? Read 2–3 neighboring files before judging.

- [ ] Follows the existing pattern for this kind of thing (error handling, config loading, logging, validation) instead of inventing a parallel one
- [ ] No duplicate helper under a new name — search for an existing one before accepting a new utility
- [ ] New code lives in the right file/module, not wherever was convenient
- [ ] Level of abstraction matches the surrounding code; a reviewer scrolling past wouldn't see a seam
- [ ] Naming, import style, and file organization match the neighbors
- [ ] The smallest change that solves the problem — no speculative config, hooks, or extension points for hypothetical needs
- [ ] **Cross-module contracts hold** — if the change adds a field/flag/key to a struct that's synced, serialized, cached, or consumed elsewhere, that member actually reaches every site it must. New control wired through to the action; new field copied in the sync function; cache/memo key updated; both sides of a producer/consumer schema agree; defaults not silently overridden by a second declaration. Enumerate, don't eyeball — see `references/contract-tracing.md`. This is the seam-between-files bug a line-by-line read never catches.

## 4. AI slop & authenticity

Tells that code was generated and not actually read. Each is a smell, not always a defect — but several together mean the change needs a careful human pass. (Claude Code carries the fuller list in the user's global `style.md`; this is the portable subset.)

- [ ] Generic names — `result`, `data`, `output`, `response_data`, `temp` — where a specific name fits
- [ ] Pointless intermediate variables: `x = compute(); return x` instead of `return compute()`
- [ ] Comments restating the code: `# increment the counter` over `counter += 1`; docstrings that just repeat the signature
- [ ] Defensive `if x is not None:` / null chains the type system already guarantees
- [ ] Leftover debugging — stray `print`/`console.log`/`fmt.Println`, commented-out code, scaffolding
- [ ] Two helpers doing almost the same thing in different files with different names
- [ ] A block that's stylistically nothing like the file it lives in (different naming, different error handling, suddenly verbose docstrings)
- [ ] Section-banner comments (`# ===== SETUP =====`) instead of functions
- [ ] Try/except that only logs and re-raises, adding nothing
- [ ] Over-explained trivial code next to under-explained hard code

## 5. Refactoring & dead code

- [ ] No copy-paste duplication that should be a shared function (third use is the threshold — two is fine)
- [ ] No god function / god file accumulating unrelated responsibilities (soft ceiling ~700 lines, but split on real seams, not line count)
- [ ] No abstraction introduced for a single caller — inline it until there's a third use
- [ ] The change doesn't orphan code: removed callers leave no dead functions, unused imports, or stale config behind
- [ ] If it's a refactor, behavior is unchanged and the diff is focused — no smuggled features, no unrelated reformatting or renames

## 6. Clarity & naming

- [ ] Names say what the thing is/does; no `tmp2`, no abbreviations only the author understands
- [ ] Functions are short enough to hold in your head; long ones split along real boundaries
- [ ] Comments explain *why*, not *what*; no comment is doing a name's job
- [ ] Magic numbers and strings are named constants where it aids understanding
- [ ] Public APIs have docstrings covering non-obvious behavior and edge cases

## 7. Error handling

- [ ] Exceptions not swallowed silently (`except: pass`, empty catch)
- [ ] Error messages are actionable — say what failed and ideally what to do
- [ ] Fail-loud where a silent failure would corrupt state or hide a bug; fail-quiet only where degradation is intended
- [ ] Retries have backoff and a cap; no infinite retry on a permanent failure
- [ ] Resources released on the error path too (`finally` / `with` / `defer`)
- [ ] Errors not over-caught: catching `Exception` where a specific type is meant
- [ ] **Trace the failure path, not just the happy path** — for each external call (I/O, network, await, subprocess, DB), ask what happens when it *fails or returns empty/partial*, and confirm that path is handled and, ideally, tested. The happy-path bias is where error handling silently doesn't exist. Inject the failure (mock the call to raise/return empty) on the riskiest one rather than assuming the handler works.

## 8. API design

- [ ] Public surface is the minimum needed; nothing exported that should be private
- [ ] Backwards compatible, or the breaking change is called out explicitly (see category 14)
- [ ] Parameter and return types are clear and hard to misuse; no boolean-trap flags
- [ ] Deprecations have a path and a timeline, not a silent removal
- [ ] Names in the public API read well from the caller's side

## 9. Performance

Flag only real problems, not micro-optimization. Correctness and clarity first.

- [ ] No N+1 queries — loops issuing one query per item that could be one query
- [ ] No repeated work that could be hoisted or memoized
- [ ] No allocations or heavy work in a hot path / tight loop that doesn't need it
- [ ] No blocking I/O on an async event loop
- [ ] Data structures fit the access pattern (list scan where a set/map is wanted)
- [ ] Pagination on anything that could return unbounded rows

## 10. Concurrency

- [ ] Shared mutable state is protected (lock / channel / actor / atomic)
- [ ] No check-then-act races (`if not exists: create`)
- [ ] Async tasks / goroutines can't leak — cancellation and timeouts propagate
- [ ] No ordering assumptions between concurrent operations that aren't enforced

## 11. Resource usage

- [ ] File handles, sockets, DB connections closed deterministically
- [ ] No unbounded growth — caches have eviction, queues have limits, buffers are capped
- [ ] Long-lived objects don't retain references that prevent collection
- [ ] Connection pools sized and not exhausted by the new code path

## 12. Logging & observability

- [ ] Log levels appropriate (not `error` for routine events, not `info` for a failure that breaks the request)
- [ ] No secrets, tokens, or PII in logs
- [ ] New operations emit enough signal (logs / metrics / traces) to debug them in production
- [ ] No log spam in hot paths

## 13. Dependencies

- [ ] A new dependency is justified — it does enough to earn its place, vs. a few lines of local code
- [ ] Actively maintained; not abandoned; license compatible
- [ ] Doesn't overlap something already in the project (a second HTTP client, a second date library)
- [ ] Lockfile updated and committed

## 14. Configuration & migrations

- [ ] New env vars / config flags documented, with sane defaults, validated at startup
- [ ] Migrations are reversible or have an explicit rollback plan
- [ ] Data backfill (if any) is correct and safe to re-run
- [ ] Breaking changes — public API, config format, DB schema — flagged explicitly so they aren't a surprise at deploy

## 15. Documentation

- [ ] README / usage docs updated when behavior or interface changed
- [ ] Docstrings on new public functions/classes
- [ ] Changelog entry if the project keeps one
- [ ] Comments referencing moved/renamed paths updated in the same change

---

## Bonus: project-specific patterns

Add conventions specific to the codebase under review. Examples:

- "Money is always `Decimal`, never `float`."
- "Handlers return a typed result object, never a bare dict."
- "Every public function has a corresponding test in the mirrored test path."
