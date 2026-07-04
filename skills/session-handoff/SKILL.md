---
name: session-handoff
description: "Generate a self-contained Markdown handoff document \u2014 plus a file inventory and proposed workspace layout if the session produced files \u2014 for moving work to another AI agent. Trigger ONLY on explicit asks: \"handoff doc\", \"session handoff\", \"I'm moving this to Claude Code\", \"wrap this up so I can continue elsewhere\". Not for generic chat summaries."
---
 
# Session Handoff
 
Produce a Markdown document that lets a *different AI agent* — possibly a non-Claude model with zero shared context — pick up exactly where this session left off.
 
The reader is not the user. The reader is the next agent. Write for them.
 
## What this doc is for
 
The user has been working with you on something substantive and now wants to continue the work elsewhere. The most common case is moving from a desktop chat app (where you have no filesystem access and no workspace) to a CLI agent like Claude Code (where the next agent can actually read files, edit code, and run commands). Other targets include fresh chat sessions, non-Claude models, or another instance of the same model.
 
Two shapes of session need slightly different handoffs:
 
- **Planning session.** The session produced ideas, decisions, and plans — but few or no files. The handoff is the plan, plus a recommended workspace layout for the next agent to *create*.
- **Building session.** The session actually produced files (artifacts, code, drafts, configs) that the user will download. The handoff is the plan, an inventory of those files, and a layout telling the next agent where each one belongs in the new workspace.
The skill handles both. Recognize which shape applies before writing.
 
## Principles
 
- **Self-contained.** Do not reference "the earlier chat" or "as we discussed." The next agent has none of that. State things plainly.
- **Model-agnostic.** Do not assume the reader is Claude. Do not reference Claude-specific features, memory, projects, or artifacts unless explaining them as external context the next agent needs to understand.
- **Capability-aware.** Assume the next agent has filesystem and command-execution access unless the user says otherwise. That's the whole reason for the handoff.
- **Don't fabricate workspace facts.** Whatever harness you're running in, you do not know where the user will run the next agent, what directory they'll start in, or what their machine looks like. Do not invent paths, repo locations, branch names, or environment details. Workspace facts go in the doc only if (a) the user mentioned them in the session, or (b) you ask the user before writing. When the user hasn't specified a workspace path, write the layout in *relative* terms (`./src/`, `./docs/`) and let the next agent anchor it.
- **Substance over ceremony.** Skip throat-clearing. The next agent should read the doc once and start working.
## Before writing: re-read the entire session
 
This is the most important step and the easiest to skip. Do not draft from impression or recent memory — scroll back through the *whole* conversation from the beginning, including the early exchanges that feel boring or irrelevant. Long sessions have a way of burying load-bearing details near the top: an early offhand decision, a constraint the user mentioned once, a file path that came up in passing, a number, an error message, a preference. The next agent will not have any of this unless you put it in the doc, and you will not put it in the doc if you don't re-encounter it.
 
Do this even if the session feels short or fresh in your context. Especially do it for long sessions where earlier turns may have been compacted or summarized away — anything that got compressed needs to be reconstructed deliberately.
 
When re-reading, watch for:
 
- Specific file paths, function names, command names, URLs, IDs, error strings
- Numeric values, version numbers, config keys
- Constraints or requirements the user stated once and didn't repeat
- Conventions the user uses (naming, tooling, style) that the next agent shouldn't have to rediscover
- Things the user noticed but didn't act on
- Decisions that were reversed mid-session — the *final* state matters, not the first attempt
- **Files you actually produced during the session** — artifacts, code blocks clearly intended as files, drafts. List them mentally before drafting the doc. These drive whether this is a planning handoff or a building handoff.
## How to handle files produced during the session
 
If the session produced files (artifacts, full-file code blocks, documents), do **not** try to regenerate them in the handoff. They already exist as their original messages or artifacts — regenerating risks drift from what the user actually has. Instead:
 
1. **Enumerate** them clearly in the "Files to bring along" section of the doc, with one line each describing what the file is, its state (complete / partial / sketch), and where in the proposed layout it should go.
2. **At the very end of your response**, after the doc, give the user a short "Files to download" reminder pointing at the files they need to grab from the session. This is so they don't have to scroll back through the conversation hunting for them.
3. **In the doc, propose a workspace layout** in relative paths (`./src/auth.ts`, `./docs/handoff.md`, etc.) and place each enumerated file in it.
4. **Tell the next agent** in the doc that files may not be in the proposed layout when it starts — the user is moving them by hand. Its first move on a building handoff is to check whether the files are where the layout says, and either move them into place or confirm the layout with the user.
If the session produced *no* files (pure planning session), skip the "Files to bring along" section and instead write a "Recommended workspace layout" section that tells the next agent what structure to create from scratch.
 
## Output format
 
Use this exact structure. Use these exact headings. If a section is genuinely empty or doesn't apply, write `_None._` or `_Not applicable — [reason]._` rather than omitting the heading. The structure itself is a contract with the next agent.
 
```markdown
# Session Handoff: [short descriptive title of the work]
 
_Generated [YYYY-MM-DD]. Handing off to: [target agent / tool, e.g. "Claude Code CLI", "fresh GPT session", "another Claude chat"]._
_Session type: [Planning | Building]._
 
## Context
 
[2–4 sentences. What is this project / task? What is the user trying to accomplish overall? Just enough orientation that the rest of the doc makes sense to someone walking in cold. No history, no narrative — set the scene and move on.]
 
## Goals & current status
 
**Goal:** [The concrete thing being worked toward, stated as an outcome.]
 
**Status:** [Where things stand right now. One paragraph max. Be specific.]
 
## Workspace & environment
 
[What the next agent will be operating in, to the extent it's known. Include only facts the user actually mentioned or that are obviously implied:
 
- Working directory or repo, if the user named one (otherwise: "Not specified — next agent should ask or default to the directory where it's invoked.")
- Language / tooling / framework, if established
- Build / test / run commands, if established
- External services, deployed environments, accounts, anything outside the conversation the next agent should know about
 
Do not invent details. If something is unknown, say so — the next agent will ask.]
 
## Files to bring along
 
[ONLY for building sessions where the user has files to download from this session. Each entry:
 
- **`./proposed/path/filename.ext`** — what the file is, current state (complete / partial / sketch), and any caveats (e.g., "imports a helper that hasn't been written yet").
 
Tell the next agent at the top of this section: "The user is moving these files into the new workspace by hand. They may not be at these exact paths when you start — your first move is to verify the layout and either rearrange or confirm with the user."
 
For planning sessions with no files produced, replace this section with **Recommended workspace layout** below.]
 
## Recommended workspace layout
 
[ONLY for planning sessions where no files exist yet. Describe in relative paths what the next agent should create when it starts:
 
```
./src/
./tests/
./docs/handoff.md   ← this document, save here for reference
./README.md         ← stub, fill from Context section
```
 
Explain *why* this layout fits the work, briefly. Keep it adaptive to the work type — a writing project looks different from a code project from a research project.
 
For building sessions, replace this section with **Files to bring along** above. Do not include both.]
 
## Key information
 
[Verbatim facts that don't fit cleanly into other sections but the next agent will need. Use exact wording; do not paraphrase. Each item self-explanatory in one line; if it needs more, give it a short heading.
 
Examples of what belongs here:
- Exact error message that's been recurring
- A function signature or schema that's load-bearing
- A specific number, ID, or URL that came up
- A naming convention or style preference the user established
- An external constraint (deadline, dependency, person who needs to approve)
 
If there's nothing essential outside the other sections, write `_None._`]
 
## Decisions made
 
[Bulleted list of decisions that have been locked in and the reasoning behind each. Format: decision, then a short "because…" so the next agent knows what's load-bearing vs. what's revisitable. Include rejected alternatives only when the rejection itself is the decision (e.g. "Not using library X because…"). Aim for around 6 most load-bearing decisions; if you have many more, you're probably mixing in things that belong in Open threads or Key information.]
 
- **[Decision]** — [why]
- **[Decision]** — [why]
 
## Considered and rejected, or tried and failed
 
[Approaches that were considered and dropped, or attempted and didn't work. Distinguish the two: "we thought about X and chose not to" is different from "we tried X and it broke." Each entry: what was considered/tried, what happened or why it was dropped, and what was learned. The point is to keep the next agent from re-walking dead ends.]
 
- **[Approach]** — [what happened / why dropped] — [takeaway]
- **[Approach]** — [what happened / why dropped] — [takeaway]
 
## Open threads
 
[Specific things that are unfinished, deferred, or noticed-but-not-addressed. Most important section for handoff — what the user is most likely to forget. Be concrete: "Profile the `render()` loop — suspected N+1 in the child component" not "performance is slow."]
 
- [ ] [Thread] — [what needs to happen]
- [ ] [Thread] — [what needs to happen]
 
## Suggested first move
 
[If there's a clearly best immediate action, name it in one short paragraph and say why. If the trajectory is unclear and you'd be guessing, write `_No clear first move — recommend the next agent confirm priorities with the user before starting._` Do not invent a confident-sounding next step just to fill the section.
 
For building handoffs, the first move usually involves verifying the file layout matches the doc.]
```
 
## After the doc: files reminder
 
For **building** sessions only, after outputting the Markdown doc, add a short reminder section in your response (not in the doc itself) listing the files the user needs to download from this session. Format:
 
```
---
**Files to download from this session before starting the next agent:**
- `auth.ts` (from the artifact "Authentication module")
- `schema.sql` (from the message earlier in this chat)
- ...
 
Drop them into your new workspace and paste the handoff doc into the next agent.
```
 
For **planning** sessions, omit this — there's nothing to download.
 
## How to fill it in
 
1. **Re-read the whole session first** (see the section above). Everything else depends on this.
2. **Decide session type** (Planning vs. Building) based on whether substantive files were produced. Mark it at the top.
3. **Distinguish what was decided from what was discussed.** Committed → *Decisions*. Live → *Open threads*. Considered-but-rejected → *Considered and rejected* only if the rejection carries a useful lesson.
4. **For failed attempts, include the takeaway.** "Tried X, got error Y, root cause was Z" is useful. "Tried X, didn't work" is not.
5. **Open threads should be actionable.** Sharpen vague ones before writing them; ask the user if you can't.
6. **Use verbatim text for anything load-bearing.** File paths, error messages, command names, function signatures, exact values — paste them as-is.
7. **Do not fabricate workspace facts.** If you don't know the user's workspace path, say so or ask.
## Length and tone
 
- Target length: 500–1200 words. Long enough to be useful, short enough that the next agent will actually read it. Building handoffs run longer because of the file inventory.
- Plain prose and tight bullets. No emoji, no marketing voice, no "I hope this helps."
- Write in third person about the user ("the user wants…") rather than first person ("we decided…"). The next agent isn't part of "we."
- Code, paths, errors, commands: include verbatim when load-bearing.
## Asking before writing
 
If after re-reading the session you're missing something critical — usually the handoff target, the user's workspace location, or whether an in-progress thread counts as "decided" vs. "open" — ask the user one focused question before generating the doc. Don't run a battery of clarifying questions; the user wanted a handoff doc, not an interview. One question, then write.
 
If everything is clear from the session, just write the doc.
 
## Delivering the doc
 
Output the doc directly in the chat as a Markdown code block so the user can copy it. If the environment supports file creation and the user prefers a file, save it as `session-handoff-[short-slug]-[YYYY-MM-DD].md` and present it — but default to inline. Most handoffs get pasted into the next tool, not attached.
 
For building sessions, follow the doc with the "Files to download" reminder described above.
 
## Example: a building handoff
 
A handoff from a Claude desktop session to Claude Code CLI, where the user was scaffolding a small Node CLI tool and has files to bring along:
 
```markdown
# Session Handoff: `repo-stats` CLI tool
 
_Generated 2026-05-13. Handing off to: Claude Code CLI._
_Session type: Building._
 
## Context
 
The user is building `repo-stats`, a small Node CLI that walks a git repo and prints contributor stats (commits, lines, files touched) as a Markdown table. Target use: drop-in for the user's monthly team retros. This session scaffolded the core structure and got a working first pass on the commit-counting logic; the lines-and-files logic is still to do.
 
## Goals & current status
 
**Goal:** A Node CLI named `repo-stats` that takes a repo path and prints a contributor stats table.
 
**Status:** Project scaffolded, package metadata set, and the commit-counting code works for simple repos. Lines-changed and files-touched logic has been sketched but not implemented. CLI entry point exists but currently only wires up commit counting.
 
## Workspace & environment
 
- Working directory: not specified. The user will start the next agent in a new workspace; default to whatever directory it's invoked in unless told otherwise.
- Node version: 20 (user mentioned `node:test` use, which is the 20+ runner).
- Package manager: npm (per the `package.json` produced).
- Run with: `node ./src/cli.js <repo-path>`. Test with: `node --test`.
 
## Files to bring along
 
The user is moving these files into the new workspace by hand. They may not be at these exact paths when the next agent starts — first move is to verify the layout and either rearrange or confirm with the user.
 
- **`./package.json`** — complete. Declares the CLI binary and dev deps.
- **`./src/cli.js`** — partial. Entry point; currently only wires up commit counting, needs the other two stat types added.
- **`./src/stats/commits.js`** — complete. Walks git log and returns a per-author commit count.
- **`./src/stats/lines.js`** — sketch only. Function signature and a TODO comment; no implementation.
- **`./src/stats/files.js`** — sketch only. Function signature and a TODO comment; no implementation.
- **`./src/format.js`** — complete. Takes the stats object and renders the Markdown table.
- **`./test/commits.test.js`** — complete. Passing.
 
## Key information
 
- The stats functions all return the same shape: `Record<authorEmail, number>`. `format.js` assumes this — keep it consistent.
- The user prefers `node:test` over Jest. Don't introduce a test framework.
- Output table is sorted by commit count descending; ties broken alphabetically by author email.
 
## Decisions made
 
- **Node CLI, no compilation step** — keep it simple, no TypeScript, no bundler.
- **`node:test` for tests** — already in Node 20+, no extra deps.
- **Shell out to `git log` rather than parsing `.git/` directly** — simpler and reliable enough for a personal tool.
- **One file per stat type** — easier to extend later (e.g., adding a `prs.js` for GitHub PRs).
 
## Considered and rejected, or tried and failed
 
- **Using `simple-git` package** — considered, rejected. Takeaway: adds a dependency for what amounts to three `git log` calls.
- **Streaming output for large repos** — considered, deferred. Takeaway: not needed at the scale the user actually runs on; revisit if it becomes slow on real repos.
 
## Open threads
 
- [ ] **Implement `lines.js`** — parse `git log --numstat` output, sum additions+deletions per author.
- [ ] **Implement `files.js`** — parse `git log --name-only` output, count unique files per author.
- [ ] **Wire both into `cli.js`** — the entry point currently only calls `commits.js`.
- [ ] **Add tests for `lines.js` and `files.js`** to match the pattern in `test/commits.test.js`.
- [ ] **Decide on email normalization** — user has different commit emails across machines; deferred for now but worth raising before shipping.
 
## Suggested first move
 
Verify the files are in the proposed layout. Then implement `./src/stats/lines.js` using `git log --numstat --pretty=format:"%ae"` — the parsing pattern is parallel to `commits.js`, which already works. Run `node --test` after each addition. Save the email-normalization question for after the basic three-stat version is working.
```
 
---
 
**Files to download from this session before starting the next agent:**
 
- `package.json` (from the artifact "package.json")
- `cli.js` (from the artifact "src/cli.js — entry point")
- `commits.js` (from the artifact "stats/commits.js")
- `lines.js` (from the artifact "stats/lines.js — sketch")
- `files.js` (from the artifact "stats/files.js — sketch")
- `format.js` (from the artifact "format.js")
- `commits.test.js` (from the artifact "commits test")
Drop them into your new workspace and paste the handoff doc into the next agent.
