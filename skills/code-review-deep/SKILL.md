---
name: code-review-deep
description: "In-depth, tool-grounded code review, distinct from the built-in /code-review. Default scope is the WHOLE codebase (runs linters/tests, reads architecture, checks for AI slop, renders a Continue/Refactor/Rebuild verdict); scopes down to a deep change review only when the user names a PR, commit, or diff. Trigger on \"deep code review\", \"review this codebase\", \"is this good code\", \"audit this project\". For \"is this exploitable?\" use security-review-deep."
---

# Code Review

A disciplined, repeatable process for reviewing code the way a good senior engineer would. By default it assesses the **whole codebase** — architecture, sustainability, and whether it should be continued, refactored, or rebuilt. Pointed at a specific change, it does a deep, tool-grounded review of that change instead. Either way it runs the deterministic tools, reads for flow and AI slop, walks a structured checklist, verifies its claims, and hands back a grounded, triaged report. Grounding in tool output and a fixed checklist is what makes it consistent instead of dependent on what the model happens to notice that day.

## When to use this skill

- Assessing a whole project: "is this good?", "is this sustainable?", "should I rewrite this?", "can someone else work on this?", "review this codebase properly"
- Inheriting or returning to a codebase and wanting an honest health verdict
- Reviewing a specific PR, commit, or diff in real depth (scope it by naming the change)
- After finishing a feature, refactor, or bug fix and wanting a real second pass
- When the user suspects AI-generated slop and wants it caught

This is the heavier counterpart to Claude Code's built-in `/code-review`. Use `/code-review` for a quick pending-diff pass; reach for this skill when the user wants a full audit — the default whole-codebase assessment, or a rigorous deep-dive on a named change — and especially when running in an agent that has no built-in review at all.

**Boundary with `security-review-deep`:** that skill asks "is this exploitable?" with an adversarial lens. This one asks "is this good code that should merge?" with a collaborative lens. They overlap on error handling, input validation, dependencies, and concurrency, but answer different questions about the same lines. Example: "this `except` is too broad" is a code-review comment; "this `except` swallows the auth-check failure and fails open" is the security finding. If you spot something security-relevant here, mention it and point to `security-review-deep` for depth — don't try to do both jobs at once.

## What to review: default to the whole codebase

**The default is a complete assessment of the whole codebase**, not a single diff. When the user points this skill at a project without naming a specific change — "review this," "is this any good," bare `/code-review-deep`, or anything in that neighborhood — assess the whole thing: architecture, sustainability, whether a new dev could work on it, how a real user interacts with it, and a Continue / Refactor / Rebuild verdict. The process, the three lenses, the macro checklist, the subagent fan-out, and the verdict format are in **`references/project-review.md`** — read it and follow it. That's the headline capability; the built-in `/code-review` is where a quick pending-diff check belongs.

**Scope down to a change review only when the user names a change** — a PR, commit, range, or "review this diff." Then run the deep change-review process below: bounded to that change, but far more rigorous than the built-in (full project toolchain, cross-file verification, claim-checking, triaged findings). Reviewing one bounded change inside a large mature repo is exactly the case where scoped review beats trying to read the whole thing — that's when to use it.

**A change review can escalate back to the default.** If a scoped review keeps turning up *systemic* rot — a half-finished migration, no tests anywhere, a God object the change just feeds, multiple crash bugs in uncommitted work — the line-by-line findings are symptoms, not the story. Stop stacking nits, say so plainly, and offer the project-level verdict: "These aren't really change-review findings; the project itself has a health problem. Want the full Continue / Refactor / Rebuild assessment?" Then follow `references/project-review.md`. Don't bury "this foundation is unsound" inside a list of Discuss items.

If you genuinely can't tell whether the user wants the whole codebase or one specific change, ask one question before starting.

## The process (change review)

Work in this order. Don't skip to opinions before running the tools and reading the whole change — that's how reviews turn into either "looks good!" or a pile of nitpicks that miss the real problem.

**Before Step 1, read `references/blind-spots.md`.** It lists the bug classes a past review here marked "clean" and that turned out to be real. For each entry whose trigger matches the code in front of you, run its named check — these aren't optional nits, they're the checks that *would have* caught a shipped bug. When a review is later found to have missed something, add an entry. This is the loop that makes the reviewer improve instead of repeating its blind spots; it applies to the whole-codebase path too.

### Step 1 — Scope the change

```bash
# PR review (against the base branch):
git diff origin/main...HEAD --stat
git diff origin/main...HEAD

# Local/uncommitted work:
git diff --stat
git diff

# Last commit:
git diff HEAD~1 HEAD
```

**Named change resolves to nothing?** You're in change review because the user named a scope — but it can come up empty (a clean working tree, a commit that's only file-mode flips, a range with no code changes). Say so plainly rather than reviewing noise. Then either point at the nearest reviewable change (e.g. the last real code commit) and confirm, or — if it turns out the user wanted a health check rather than a specific change — switch to the default whole-codebase assessment in `references/project-review.md`. Remember the skill's default is the whole codebase; you only narrowed to this scope because a change was named, so if that scope is empty, the whole-codebase pass is usually what they actually want.

Capture the list of changed files and classify the change: feature / bug fix / refactor / dependency bump / breaking API change / docs. The classification sets expectations — a refactor that adds behavior is a smell; a feature with no new tests is a smell.

The classification also shifts where the weight of the review goes:

- **Refactor** — the dominant question is *behavior preservation*, not "did it add tests." Run the moves-only verification below before anything else; logic that drifted during a "pure move" is the bug this review type exists to catch.
- **Feature** — weight Step 4 (tests) and the correctness/error-handling categories; a feature with no negative-path test is the default finding.
- **Dependency bump** — weight the dependency and security angle: is the new version maintained, does it pull new transitive deps, does the changelog mention a CVE or a breaking change? This is the one change type where `security-review-deep` overlap is worth a glance.
- **Breaking API change** — weight API design + migration: deprecation path, version bump, callers updated, changelog entry.
- **Bug fix** — weight the regression test that pins the bug, and whether the fix treats the cause or the symptom.

### Step 2 — Run the deterministic tools

Let the tools find what tools are good at finding, so your attention is free for what they can't.

**Prefer the project's own commands** over the skill's defaults. Look for a `Makefile`, `justfile`, or `package.json` scripts named `lint` / `test` / `typecheck` / `format`, and a CI config (`.github/workflows`, `.gitlab-ci.yml`). The project knows its toolchain better than any default. Fall back to the per-language defaults only when nothing is configured:

- **Python** — `ruff check`, `mypy` or `pyright`, `pytest`, `radon cc` (complexity), `vulture` (dead code)
- **JS/TS** — `eslint`, `tsc --noEmit`, `prettier --check`, `vitest`/`jest`, `knip` (dead code/exports)
- **Go** — `gofmt -l`, `go vet`, `staticcheck`, `go test`, `errcheck`
- **Rust** — `cargo fmt --check`, `cargo clippy`, `cargo test`
- **Ruby** — `rubocop`, `rspec`
- **Java** — `spotbugs`, `checkstyle`, `pmd`, the project's test task
- **Dockerfiles** — `hadolint` (catches unpinned bases, missing `--no-install-recommends`, layer/cache mistakes, missing runtime deps)
- **Shell scripts** — `shellcheck` (quoting, word-splitting, unset-var, portability bugs)

If a tool isn't configured in the project, **provision it before giving up** — `uvx ruff check`, a throwaway venv, `npx`, `pytest --cov`. A one-off install is cheap, and "no linter ran" is a weak line in an audit when the tool is one command away. Only after that genuinely fails do you note it unavailable and move on. Don't refuse to review. Capture each tool's output and treat failures as findings, not blockers.

**Optional, for a large finding set with a local model available:** run the scanners broad-and-noisy and hand the raw output to a local model to cluster, drop obvious false positives, and rank — then adjudicate only the shortlist on the frontier model. This is the recall→triage→judgment split that saves tokens on the tedious part. The local model triages; it never renders correctness verdicts (it mis-calls exactly the cross-module bugs this skill targets). Setup and the hard boundary are in `references/scanner-triage.md`. Skip it with no penalty beyond cost if no local model is running.

**Run the code where the risk is dynamic — don't assess it by reading alone.** Linters won't catch a broken LLM/agent retry loop, an async ordering bug, or a runtime crash on a path the tests skip. For the riskiest runtime logic — agent/LLM orchestration, background jobs, anything with no test around it — exercise it: mock the model or external call, replay a fixture, or run the one path in a REPL. "Assessed by reading only, no API key" is the most common way a review misses the real bug. If you truly can't run it, say so loudly in the report rather than implying you verified it.

**For UI and stateful changes, run the app and watch the behavior — reading is not enough, and neither is a static trace.** A toggle that does nothing, a default that doesn't take effect, a control wired to the wrong action, a cluttered first screen: none of these show up in the diff, and some don't even show up under the cross-module trace in Step 3c because the code reads as correct. The only thing that catches them is launching the app and observing — click the control, check the default actually applies, read the first screen a real user sees. Two of the worst Orbitron bugs (a hardcoded default silently overriding the real one; a cache key that returned stale data on toggle) survived *both* a deep review and an adversarial static audit, and were caught only by running the fixed code and seeing the change not happen on screen. Use the `verify` skill or `references/project-review.md`'s run step. And critically: **after applying a fix, re-run and confirm the behavior actually changed.** "It compiled and the code looks right" is exactly the trap — a clean build after a fix proves nothing about whether the fix worked.

The same blind-spot applies to artifacts whose only real test is execution: a **Dockerfile you can't `docker build`**, a CI workflow that only runs on push, a migration you can't apply against a real DB. The static linter (`hadolint`, `shellcheck`, `actionlint`) catches surface bugs, but "the runtime dependency is missing" or "the build stage can't see that file" only shows up on a real build. When you can't run it, flag the change as statically-reviewed-only in the report — don't let a clean `hadolint` pass read as "this image builds."

**Runtime tools — enable when the change touches concurrency, memory, async, or non-determinism.** Static linters miss races, leaks, and undefined behavior. When the diff touches those areas, run the relevant runtime tool alongside the test suite:

- **Go** — `go test -race ./...` whenever the change touches goroutines, channels, shared maps, or sync primitives. Mandatory, not optional.
- **C/C++** — rebuild with `-fsanitize=address` for memory bugs, `-fsanitize=thread` for races, `-fsanitize=undefined` for UB. Run the tests; sanitizer output is a finding.
- **Rust** — `cargo miri test` when the change adds or modifies `unsafe`. The borrow checker covers the rest at compile time.
- **Python** — `tracemalloc` for memory growth in long-lived processes; `asyncio.get_event_loop().set_debug(True)` (or `PYTHONASYNCIODEBUG=1`) for async ordering bugs.
- **JS/TS** — heap snapshots in Node DevTools when the change touches long-lived caches, closures, or event listeners.

If the diff doesn't plausibly touch any of these surfaces, skip. The point is to reach for the right tool when the change shape calls for it, not to run every sanitizer on every diff. For deeper bug-shape coverage, see `bug-hunter`'s "Reach for the right runtime tool" section.

### Step 3 — Read the change as a whole

Before line-level nitpicking, step back. Most reviewers (human and AI) never do this, and it's where the highest-value findings hide.

- What is this change *trying* to do? Restate it in one sentence. If you can't, that's a finding.
- Trace the main path through the new code. Does the control and data flow make sense, or does it wander?
- Does it fit the codebase, or does it look bolted on? Read 2–3 neighboring files. A change that introduces a second config loader, a parallel error-handling style, or a duplicate helper under a new name is fragmenting the codebase even if every line is "correct."
- Is this the smallest change that solves the problem, or is there speculative generality — config options, hooks, abstractions for one caller?
- Would the next person understand it in 30 seconds? If not, the problem is usually structure or naming, not a missing comment.

### Step 3b — If it's a refactor, prove it's behavior-preserving

For a change that *claims* to be a pure refactor (a file split, a rename, a move, an extraction), "I read it and it looks like a move" is not verification — a one-character operator flip hides perfectly inside a 1,700-line move. Use a mechanical line-set diff: a true move cancels out, leaving only the scaffolding.

```bash
# Per commit (or per file). Normalize away whitespace, sort, and compare
# removed vs added lines. A pure move => the two sets are near-identical.
git show <commit> -- '*.rs' | grep '^-' | grep -v '^---' | sed 's/^-//;s/^[[:space:]]*//;s/[[:space:]]*$//' | sort | uniq -c | sort > /tmp/removed.txt
git show <commit> -- '*.rs' | grep '^+' | grep -v '^+++' | sed 's/^+//;s/^[[:space:]]*//;s/[[:space:]]*$//' | sort | uniq -c | sort > /tmp/added.txt
diff /tmp/removed.txt /tmp/added.txt   # only the asymmetric lines remain
```

Classify every asymmetric line as **benign** or **suspicious**:

- **Benign**: new module/header comments, `mod`/`import`/`use` declarations, visibility prefixes added to a moved item (`pub(super)` etc.), changed module-path prefixes on a call (`overlay::f` → `super::overlay::f`, same function and args), and formatter re-wraps (a signature that went multi-line — the tokens still all appear).
- **Suspicious**: any change to an expression, operator, literal, condition, call argument, control-flow, or constant; any removed body line with no matching added line. These are the only things that can change behavior in a "move," so they get quoted verbatim and verified against the code.

For a multi-file split this is the highest-confidence check you have, and it's cheap enough to fan out one verifier per commit (see "When the diff is huge"). When the asymmetric set is all-benign, state that as the finding: "verified moves-only, no logic drift." Watch especially for numeric constants and formulas in math-heavy code — those are where a silent drift does the most damage and an eyeball misses it.

### Step 3c — Trace the cross-module contracts

The findings a line-by-line read *cannot* reach are the ones that live in the seam between two files: a field set in one struct but never copied into the struct that consumes it, a cache key that hashes a subset of the fields its output depends on, a GUI export the CLI silently ignores, a default declared in two places where one wins. Each site reads correctly alone; the bug is the gap between them. Reading harder never finds these — you'd need foresight about which field flows where. Replace foresight with enumeration: list every member at every site and let the asymmetry be the finding.

Run this whenever the change touches **state that crosses a boundary** — UI state synced to a render/model layer, config read by more than one consumer, a producer/serializer paired with a separate reader, a cache/memo key derived from some struct, or a default that could be set in two places. The full method (how to find the hubs, the grep/AST enumeration recipes, the four asymmetry classes, and why the fix is an invariant test rather than a one-off patch) is in **`references/contract-tracing.md`**. This pass is mostly deterministic and nearly free, and on a large stateful codebase it's where the highest-value findings hide — don't skip it because the diff "looked clean." It is the single biggest reason a thorough review still misses bugs.

### Step 4 — Tests-of-the-change analysis

The single highest-leverage step, and where most AI reviews fall down. Don't accept "there are tests" at face value.

- Did the change add tests? Diff the test files alongside the source.
- Do the new tests actually exercise the new code path? Cross-reference function names and imports — a test that imports the module but never calls the changed function proves nothing.
- **Find the most fragile line and check it's covered.** Tests cluster on the happy path; the bugs hide in the clever bit. Pick out the trickiest logic in the change — the special-case guard, the fallback branch, the off-by-one boundary, the bit with a comment explaining why it's subtle — and confirm a test pins it. An untested guard is one refactor away from silently vanishing. This single question surfaces more than the rest of the step combined.
- Did existing tests change? Distinguish "updated expected value because behavior legitimately changed" from "weakened the assertion to make it pass."
- Any trivially-passing tests? `assert True`, no assertions at all, asserting on a mock you just configured, asserting `x == x`.
- Is each happy-path test paired with a negative/error-path test?
- Run coverage when it's available and **cite the actual number — don't estimate** "~80% covered" from eyeballing. `pytest --cov`, `cargo llvm-cov`, `vitest --coverage` scoped to the changed files. A measured figure is a finding; a guessed one is noise.

**Coverage is necessary, not sufficient — for the fragile bit, mutation-test it.** A line can be 100% covered by a test that would still pass if the logic were wrong (the happy-path-clustering trap that lets real bugs through). The rigorous check is mutation testing: flip a `<` to `<=`, delete a branch, negate a condition, and see if any test fails. A surviving mutant is a hole the suite can't see. Run it scoped to the trickiest changed module, not the whole repo (it's slow): `cargo mutants` (Rust), `mutmut` / `cosmic-ray` (Python), `stryker` (JS/TS). A surviving mutant on a load-bearing branch is a Block/Request-changes finding, not a nit. And close the loop the way Meta's mutation-guided generation does: when a mutant survives, the fix isn't "note it" — it's **write the test that kills it**, then confirm that test fails on the mutant and passes on the real code. Reserve this for changes where a silent regression would actually hurt (parsers, math, money, security guards, state machines); skip it on glue code.

### Step 5 — Walk the review checklist

For **every changed file**, walk the checklist in `references/review-checklist.md`. For each category, mark ✅ cleared (with a one-line reason), ⚠️ flagged (with `file:line` + explanation), or N/A. Naming what you checked is the point — "looks good" with nothing behind it is the failure mode this step exists to prevent.

The categories, in priority order:

1. **Correctness & logic** — off-by-one, null/None, boundary cases, error paths, async ordering, transaction boundaries, and plain bad logic: conditions that can't be true, inverted checks, dead branches, convoluted control flow that should be flat.
2. **Tests** — covered in depth at Step 4; record the verdict here.
3. **Code flow & coherence** — does it fit the architecture, or fragment it? Duplicate helpers, parallel mechanisms, wrong-file placement, and cross-module contracts (a new field/flag/key reaching every site it must sync/serialize/cache to — see Step 3c).
4. **AI slop & authenticity** — the tells that mean code was generated and not read: `result`/`data`/`output` names where a specific one fits, `x = f(); return x`, `# Increment counter` over `counter += 1`, defensive `if x is not None` the types already guarantee, leftover debug prints, two near-identical helpers, a block that looks nothing like the file around it.
5. **Refactoring & dead code** — duplication, god functions/files, abstractions with one caller, code the change leaves orphaned.
6. **Clarity & naming** — names, function length, comments that explain *why* not *what*, magic numbers.
7. **Error handling** — swallowed exceptions, unhelpful messages, fail-loud vs. fail-quiet, retry logic.
8. **API design** — public surface, backwards compat, deprecation, versioning.
9. **Performance** — N+1 queries, repeated work, allocations in hot paths, blocking I/O on an event loop.
10. **Concurrency** — races, shared mutable state, lock discipline, ordering assumptions.
11. **Resource usage** — leaked handles/connections, unbounded growth, missing cleanup.
12. **Logging & observability** — levels, no secrets/PII in logs, signals for new operations.
13. **Dependencies** — new dep justified, maintained, licensed, not overlapping an existing one.
14. **Configuration & migrations** — new flags documented and validated; migrations reversible with a rollback path.
15. **Documentation** — README/docstrings/changelog updated when behavior changed.

### Step 6 — Triage and output the report

Sort every finding into one bucket, then write the report using `references/report-template.md`. Lead with the verdict, then the worst finding. Length follows findings — a clean change gets a short report.

**The five buckets:**

- **Block** — must fix before merge. Correctness bugs, broken or missing tests for new code, a breaking API change with no deprecation, failing CI.
- **Request changes** — should fix before merge. Clarity that will hurt the next reader, real perf problems, missing error handling, unclear public names.
- **Discuss** — design questions worth a conversation, not blocking.
- **Nit** — style, minor naming, formatting. Take or leave. Label them so the author knows they're optional.
- **Praise** — call out what was done well. Not optional. A review that only ever criticizes burns out the person receiving it, and praising good patterns reinforces them.

**Separate change-introduced from pre-existing (baseline discipline).** On a change review especially, distinguish a finding the change *introduced* from one that was already in the code it touched. They're both worth knowing, but they carry different weight: a bug the change adds blocks the change; a pre-existing bug in a neighboring line is a backlog item, not a reason to hold this merge. Mark pre-existing findings as such and group them at the end. This is the discipline professional scanners encode as a baseline — it's what keeps a review from drowning a small change in the accumulated debt of the file around it, which is the fastest way to get a review ignored wholesale.

## Tone guardrails

These are load-bearing. A code review that ignores them is either useless or insufferable.

- **Don't pile on.** If a function has eight problems, give the top three, then group the rest: "and 5 similar naming issues in this function." A wall of findings gets ignored wholesale.
- **Separate "wrong" from "I'd prefer."** Heuristic: if you're about to write "I would...", it's a preference — make it a Nit or drop it. Reserve Block and Request-changes for things that are actually wrong.
- **Read charitably.** If something looks odd, assume there's a reason and ask, rather than flagging it as a mistake. Surprising code is sometimes load-bearing.
- **Defer style to the project's tools.** Don't hand-flag formatting the linter/formatter owns. If the project has no formatter, that's one finding, not forty.
- **Praise honestly.** Don't manufacture it, but don't skip it when it's earned.

## Failure modes to actively avoid

- **"Looks good to me."** If you haven't run the tools, read the whole change, and checked the tests, you don't know that.
- **The 40-nitpick review.** Triage discipline exists to prevent this. Group and cap.
- **Reviewing the diff blind to the codebase.** A change can be locally clean and globally wrong (duplicates an existing helper, breaks a convention). Step 3 is not optional.
- **Trusting "there are tests."** Step 4 is where you verify they test the actual change.
- **Rewriting the author's code.** Suggested fixes are small inline snippets showing the idea, not "here's your whole function rewritten my way."
- **Confident nonsense about behavior.** If you're unsure whether something is a bug, say so and frame it as a question.

## Lightweight mode

When the user wants something fast (pre-commit, sub-minute):

1. Run only the formatter check, the linter, and the test runner on the diff.
2. Do Step 3 (read as a whole) and Step 4 (tests) — they're cheap and high-value.
3. Walk only categories 1–5 of the checklist.
4. Output a one-screen report: verdict + Block/Request-changes items only.

Tell the user it was the lightweight pass and a full review can follow.

## When the diff is huge

Over ~2000 changed lines, say so up front and offer to either (a) review by directory in batches, or (b) focus first on the files most likely to carry risk — anything matching the change's core logic, plus `*migration*`, `*auth*`, `*payment*`, schema files, and public API surfaces. Don't pretend to have deeply reviewed 5000 lines in one pass.

For a large diff you can also **fan the reading out to subagents** — one per area or risk cluster, each with a clean context returning a bottom line plus `file:line` evidence — and synthesize the findings yourself. The orchestration pattern is the same one project review uses; see the subagent section in `references/project-review.md`. One rule is non-negotiable in either mode: **verify every delegated claim before it enters the report.** Subagents misread line numbers, contradict each other, and invent bugs that aren't there. Re-check each high-severity finding against the actual code, discard the false positives explicitly, and never ship "an agent said X" — if you couldn't verify it, either verify it or cut it.

This cuts both ways: a strong **negative** conclusion on a risky change is also a high-stakes claim. "This 1,700-line refactor is moves-only" or "the parser has no untested branch" can be just as wrong as a false bug, and there's no finding to make you look twice. When a subagent clears something that matters, spot-verify the clearance yourself — re-run the line-set diff, re-grep the count, read the one function it swore was identical — before you let "all clean" into the verdict.

**Prime the subagents to be skeptical — how you prompt them decides what comes back.** A general-purpose subagent defaults to *congratulatory*: it calls code "professional-grade / production-ready / merge-ready," skims past the duplicate helper two files over, and buries the one real issue under reassurance. A review fan-out built on those is worse than no fan-out, because it launders praise into a verdict. Every review/scan subagent prompt must: forbid praise verdicts (no "looks good," no "clean" without a specific reason); demand `file:line` evidence and a quote for every claim; tell it to read the project's enforced conventions first so it doesn't flag house style as a defect; and require a position-taking bottom line, not a hedge. Prefer the purpose-built **`code-skeptic`** agent (whose system prompt bakes all this in) over `general-purpose` for these workers — and still verify its findings, because a skeptic can over-flag just as a booster under-flags.
