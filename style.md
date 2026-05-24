# Coding style and conduct

## Comments
- Comment *why*, never *what*. If the code shows what it does, the comment is noise.
- No section banners (`# ===== SETUP =====`). Use functions.
- No restating the function signature in a docstring. Docstrings explain
  non-obvious behavior, edge cases, or *why* — not the obvious.
- No "TODO: implement" stubs. If it's not implemented, don't write it.
- No emojis in code or comments unless they were already there.

## File headers
- New files start with a short comment block (2–5 lines) summarizing what
  the file is for and, if useful, how it fits with neighboring files.
- Plain prose. No ASCII borders, no author/date/version metadata, no
  changelog. Git tracks that.
- If the filename and the first export already make the purpose obvious,
  skip the header. Don't write `# user.py — handles users`.

## Matching existing code
- Before writing anything, read 2–3 nearby files. Match their patterns:
  naming, error handling, import style, file organization, test style.
- If the project uses `snake_case`, don't introduce `camelCase` "because
  it's a class method." Consistency beats convention.
- If existing code is terse, be terse. If it's verbose with docstrings
  everywhere, match that. Don't impose a different taste.
- When unsure between two patterns visible in the codebase, ask which to follow.

## Don't fragment the codebase
This is the most common AI tell at the structural level: each new section
looks like it was written by a different person with different taste.
Before adding anything new, check:
- Does a function/helper/type for this already exist? Don't write a second one.
- Does the codebase already have a *pattern* for this kind of thing
  (error handling, config loading, logging, retries, validation)? Use it.
  Don't invent a parallel mechanism because it's "cleaner."
- Does the new code's shape — file layout, naming, level of abstraction —
  match the surrounding code? If a reviewer scrolled past, would they
  notice a seam?
- If you're about to add a utility, search the codebase first. Duplicate
  helpers with slightly different names is the #1 sign of AI-grown code.

## Structure and file size
- Soft ceiling: ~700 lines per file. Past that, stop and ask whether the
  file is doing too many things. Usually it is.
- Watch for "God" files and "God" functions — anything that's accumulated
  responsibilities until no one wants to touch it. Splitting is often the
  right move, but split along *real* seams (distinct responsibilities),
  not arbitrary line counts.
- Don't pre-split. A 200-line file with one job is fine. Don't break it
  into five files to look "modular."
- When creating a new directory, consider whether a short `README.md`
  would help — what lives here, what doesn't, how the pieces relate.
  Only add one if it actually helps; an empty "this folder contains
  files" README is worse than nothing.

## Writing new code that lasts
When adding a function, module, or subsystem, ask:
- Who else will call this? If only one caller, inline it or keep it local.
  Wait for the third use before generalizing.
- What's the smallest version that solves the problem in front of me?
  Build that. Don't add config options, hooks, or extension points for
  hypothetical future needs.
- Will the next person reading this understand it in 30 seconds? If not,
  either the code or the naming needs work — not a longer comment.
- Does this belong here, or somewhere else? New code in the wrong file
  costs more later than thinking about placement now.

## Refactoring
- Refactors change structure, not behavior. Don't add features, don't
  "improve" naming of untouched code, don't reformat unrelated lines.
- A refactor PR should have a small, focused diff. If the diff is huge,
  split it or stop.
- Don't introduce abstractions for one caller. Wait for the third use.
- When restructuring, moving, or renaming: update the docs in the same
  change. READMEs, comments referencing old paths, examples in docstrings,
  architecture notes. Stale docs are worse than missing ones.

## Defensive code
- Don't wrap things in try/except just to log and re-raise. That's noise.
- Don't validate inputs the type system already validates.
- Trust callers within the same codebase. Validate at boundaries (user
  input, network, disk) — not between internal functions.

## Things that scream "AI wrote this"
- Variable names like `result`, `data`, `output`, `response_data` when a
  specific name fits.
- Pointless intermediate variables: `x = compute(); return x` → `return compute()`.
- Restating the obvious: `# Increment counter` above `counter += 1`.
- Defensive `if x is not None:` chains where the type already guarantees it.
- "Helpful" print/log statements added during implementation and left in.
- Renaming things during an unrelated change.
- Two helpers that do almost the same thing, in different files, with
  different names. (See: "Don't fragment the codebase".)
- New code that looks stylistically nothing like the file it was added to.

## When stuck
- Ask. Don't guess and produce 200 lines of plausible-looking wrong code.
- Show the smallest possible thing first, then expand if it's right.
- If a fix fails, don't try a variation of the same fix. Each failed
  attempt is evidence the theory is wrong, not that the fix was slightly
  off. Stop, re-examine what you assumed, then try a different theory.
  Two failed fixes on the same theory means abandon the theory entirely
  and widen the view (read more of the surrounding code, check the data
  flow further upstream, question framework assumptions). Never make a
  third attempt on the same theory — that's thrashing.
