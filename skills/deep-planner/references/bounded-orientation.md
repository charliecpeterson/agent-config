# Bounded codebase orientation

Loaded by `../SKILL.md` during Phase 0 (and any case where existing code or
docs are worth understanding). Load once; it stays in context for the rest
of the session. The rule everything here serves: a **bounded** read scoped
to the confirmed Goal, never a full inventory.

For small code and small docs (one or two manifests, a short
README, a handful of source files), read directly: top-level
package manifest (`package.json`, `pyproject.toml`, `Cargo.toml`,
`go.mod`, `Project.toml`, etc.), the README, the top-level
directory layout, maybe one or two key source files.

**For substantial codebases (many modules) OR large documents
(design docs, architecture docs, READMEs over ~200 lines), prefer
parallel `Explore` agent fan-out** over reading content into the
conductor's context. (`Explore` is Claude Code's built-in read-only
search agent type — no definition file in `agents/` is needed.) The agents read; their summaries enter your
context. You never pull the bulk of the codebase or a multi-page
design doc into the main conversation.

Dispatch Explore with focused questions tied to the Goal, not
"inventory everything." Examples:

- Goal is "ship binary releases" → ask Explore agents about
  release infrastructure, distribution, CI, install story.
- Goal is "add a feature" → ask about the relevant subsystem
  only.
- Goal is "security audit" → ask about the attack surface,
  trust boundaries, input handling.
- Goal is "summarize what this project does" → one Explore
  agent for the public surface and entry points.

Avoid the temptation to "do a full inventory while we're here."
That's exactly the unscoped-orientation failure mode this rule
exists to prevent.

## Fan-out output discipline

When dispatching multiple Explore agents, two rules with teeth.
Forget them and the fan-out's whole token-savings story collapses.

**Rule 1: Disjoint slices.** Each agent gets a non-overlapping
capability slice and reports capability only. Cross-cutting work
(competitor comparison, ranking, gap identification, synthesis)
happens **once in the conductor's context** after all agents
return. Don't ask four agents "what's missing vs. competitor X"
and get four overlapping comparison tables you then have to merge.

**Rule 2: Hard summary constraints in every dispatch prompt.**
Paste this block verbatim into every Explore (or generic Agent)
prompt that involves reading code or docs:

> Constraints on your report:
> - ≤150 words per question asked.
> - Raw findings only. No executive summary, no tables, no
>   star-ratings, no per-competitor comparison matrices, no
>   file-path appendix.
> - If you'd write a heading, you're being too thorough. One
>   short paragraph per finding.
> - Synthesis is the conductor's job. Report what you found;
>   do not interpret, rank, or compare.

Without these constraints, agents default to dumping multi-page
reports into the conductor's context, which defeats the
lazy-loading architecture this skill is built around.
