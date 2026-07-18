---
name: writing-architect
description: "Macro-first pipeline for multi-page documents where structure matters as much as prose (proposals, papers, grants, reports): intake -> outline contract -> draft -> developmental, structural, specificity, voice, and persona reviews -> human-writer copy pass. Trigger on \"deep writing pass\", \"this reads like AI even with no AI tells\", or any long-form piece for a specialist audience. Under ~1 page use human-writer; for critique only, editor."
---

# Writing Architect

Your job is to make a long document read like the person who actually does
the work wrote it. Not like a competent AI that summarized their abstracts.

The bar: a domain expert reviewer reads the result and never wonders if a
human wrote it. They might disagree with the argument, but they will not
suspect the author of being an outsider.

`human-writer` catches sentence-level AI tells. This skill catches the
problems that survive a clean copy edit:

- Over-explaining things the audience already knows.
- Naming categories where a specialist would name instances ("DFT" with no
  functional, "ligands" with no specific ligands, "broader pairs" with no
  pairs named).
- Hedging on anything the AI couldn't invent, instead of asking the user
  for the real value.
- Sections that don't earn their place. Arguments that accrete rather
  than build.
- Voice that drifts from how the user actually writes when they're not
  being assisted.

Run the stages in order. Each stage assumes the prior stage is clean. Do
not skip stages because the draft "looks fine" — the failures this skill
targets are invisible without these passes.

---

## Boundary with adjacent skills

- **`human-writer`** runs *inside* this skill at the copy-edit stage. Do
  not invoke it earlier. Do not duplicate its work here.
- **`editor`** runs at the very end as a final critique. Useful when the
  user wants a notes-style review before they call the doc done.
- **`deep-planner`** is upstream of this skill. It plans what the doc
  should be; this skill picks up from "we know what we want to write."
  If the user is still figuring out what to write, redirect to deep-planner.
- **`presentation-designer`** owns slide decks. Long-form prose only here.

---

## When to engage versus pass

Engage when:
- Document is more than ~1 page and structure could be the issue.
- Audience is specialist (peers, reviewers, technical readers).
- The user says the prose "reads like AI" but can't point to specific tells.
- A previous human-writer pass produced output the user didn't trust.

Pass to `human-writer` when:
- It's an email, Slack message, short post, single paragraph.
- The user wants a fast rewrite, not a multi-pass review.
- The draft is short enough that there's no structure to review.

If unsure, ask one question: "How long is the document, and who's the
audience?" The answer makes the call.

---

## Stage 0: Intake

Before any drafting or review work, gather four things. Ask only what you
need — if the user already provided some of this in their initial message,
don't ask again.

### Document profile
- What kind of document? (proposal, paper, memo, report, etc.)
- Page or word limit, required sections, deadline.
- Is there an existing draft, or are we starting from scratch?

### Audience profile
- Who reads this? Their job, their expertise, what they already know,
  what they care about, what they'll skim versus read carefully.
- For a grant: the panel composition. For a paper: the journal's typical
  reviewer. For a memo: the specific recipient.

The audience profile drives the specificity audit. Without it, the skill
can't tell over-explanation from helpful explanation. Press for specifics
if the user gives vague answers ("smart technical people" is not enough —
which field? what subfield? what's their daily work?).

### Voice samples
Ask the user to paste or point to 2–3 paragraphs of their own prose in
the same register — published work, prior abstracts, a paragraph from a
paper they wrote. Not topic-related summaries, not AI-assisted prose
they already accepted. Their own writing, raw.

These samples drive voice-matching in the later passes. If the user has
no samples (first-time author, new register), say so and proceed without
voice priming — the skill works without it but is more reliable with it.

### Cannot-invent list

The most important intake step. **Enumerate the domain commitments the
AI must not invent.** The list depends on the doc type. For each category,
ask whether the user has the real value or wants to mark it TBD.

**Load `references/intake-templates.md`** when starting intake. It
contains starting-point cannot-invent lists for the common document
types: computational chemistry, ML/AI paper, biomedical proposal,
general academic paper, internal memo, technical white paper. Pick the
template that matches the user's doc, walk it category by category,
and adapt where the user's work differs from the template.

If the user's doc type isn't in the templates file, build the list
from scratch using the framework at the top of that file ("what
specific values would a domain reviewer expect to see, and what would
they conclude if I made them up?").

Treat the user's answers as ground truth. Anything not supplied gets a
placeholder like `[FUNCTIONAL: TBD]` in the draft, never silently
filled with a plausible-sounding default.

This step alone fixes the worst failure mode. Most AI proposal drafts
fail because the AI wrote around uninventables instead of marking them.

---

## Stage 1: Outline contract

For any doc longer than two pages, produce a structured outline before
drafting. Sign-off required.

Format:
```
Section 1: <name>
  Intent: <one sentence on what this section accomplishes>
  Key facts to land: <2–4 bullets of the specific content>
  
Section 2: <name>
  ...
```

Present the outline. Ask the user three questions:
1. Are any sections missing?
2. Are any sections doing nothing the reader needs?
3. Does the order build, or does it just accrete?

Wait for explicit confirmation before drafting prose. Structural problems
are cheapest to fix here.

---

## Stage 2: Drafting

Draft section by section, in order. Each section uses:
- The audience profile (so register is calibrated from the start).
- The voice samples (so register matches the user's actual writing).
- The cannot-invent list (so placeholders go in instead of inventions).

After each section, do not move to the next until you have:
- A draft of that section in the doc.
- A short status line: "Section drafted. Placeholders inserted for: X, Y, Z."

Then check in with the user. They can correct or supply missing values
before you draft the next section.

This is slower than batch-drafting the whole doc. That is deliberate.
Catching problems early costs less than rewriting.

If the user already has a draft and wants you to operate on it, skip
drafting and proceed to Stage 3.

---

## Stages 3 through 6: Review passes (sub-agent dispatches)

Stages 3 through 6 each dispatch sub-agents from `~/.claude/agents/`
and synthesize their JSON for the user:

- **Stage 3, developmental review** (`developmental-reviewer`, runs
  alone): reverse outline, alignment issues, missing sections,
  argument flow. Apply approved structural changes before Stage 4.
- **Stage 4, structural review** (`structural-reviewer`, runs alone):
  section spine, promise-payoff, tiered findings.
- **Stage 5, specificity audit + voice match** (`specificity-auditor`
  and `voice-matcher`, in parallel): outsider-voice patterns, and
  drift from the user's voice samples (voice pass only when samples
  exist).
- **Stage 6, persona-reader simulation** (one `persona-reader` per
  audience segment, in parallel): reader-experience gaps per persona.
  Loads `references/persona-library.md`.

**Load `references/review-stages.md` when entering Stage 3.** It
carries the full protocol for all four passes: dispatch invocations,
return schemas, synthesis and presentation steps, and the gate
conditions between stages. Load once; it stays in context through
Stage 6.

Two rules apply at every stage: present the findings and wait for
user direction before moving on, and never run a pass inline in your
own context (context isolation is the point). If a sub-agent returns
`{"error": "missing_input", ...}`, gather what it needs and re-invoke.

---

## Stage 7: Copy-edit handoff

The draft is now structurally sound, audience-calibrated, specific,
and persona-tested. This is where `human-writer` does its sentence-
level pass:

- AI tells (vocabulary, sentence patterns, em dashes, etc.)
- Rhythm and cadence
- Throat-clearing and boilerplate closings

Delegate explicitly. Do not duplicate `human-writer`'s checks here. Pass
the draft and the voice samples; let it run.

Then optionally pass to `editor` for a final critique-style review. If
`editor` returns clean, the doc is done. If it returns findings, those
are typically structural problems that slipped through earlier stages —
loop back to Stage 3 if so.

---

## Stage 8: Iterate or finalize

Two halt conditions:
- User calls it done.
- Critical findings list is empty across Stages 3, 4, 5, 6, and 7.

If looping, return to the earliest stage with unaddressed findings. A
new section addition triggers a fresh Stage 1 outline check on the
affected area; a structural rewrite triggers Stage 3 on the rewritten
sections; specificity or voice findings without structural changes can
loop inside Stage 5. Persona-reader divergence usually loops back to
Stage 3 or 5, not just a copy edit.

Cap at three full pipeline iterations per session. If the doc still
isn't right after three, the underlying problem is usually that the
intake was wrong — incomplete audience profile, missing voice samples,
or an unrealistic outline. Surface that and re-intake.

### Producing the clean copy

A working draft carries scaffolding the final document must not: `TODO`
callouts, `[bracketed]` placeholders, intake notes, leftover
cannot-invent reminders. Finalizing strips all of it into a clean copy,
either a separate file (`paper-clean.md`) or, once the doc is in Word, by
deleting the callout paragraphs in place. Do this only when the user
calls the content done. Every placeholder must be filled or cut first: a
clean copy with an invented value is worse than a visible `TODO`.

---

## Operating notes

### Default editing surface, and the handoff to Word

Markdown first, not Word. The office-mcp friction with paragraph styles,
heading insertion, and font sizing eats time, so draft in `.md`, run
every review pass on `.md`, and convert to `.docx` only when the content
is settled.

The conversion mechanics (the pandoc reference-doc recipe, the
conversion-artifact cleanup pass) live in `references/word-handoff.md`;
load them when the content is settled and it's time to convert.

The handoff is one-directional. Once the user starts editing the `.docx`
in Word, that file becomes the source of truth. Do not regenerate it from
the `.md`, which would clobber their edits; read the live document (via
the office MCP) before changing anything, edit it in place, and treat the
`.md` as stale. If they only want light Word edits up front, warn that
live editing is slower and confirm before mid-document inserts.

### Structured output between stages

Each review pass produces JSON with a known schema (see each sub-agent's
own file). The skill consumes that JSON and presents findings to the
user — it does not paraphrase the sub-agent's review back into free
prose. Free prose loses the location and evidence-quote fields the user
needs to act.

### Sub-agent dispatch

Dispatch mechanics and per-stage parallelization are in the stage map
above and in `references/review-stages.md`. The rule behind them:
within a stage, dispatch in parallel (independent jobs; the orchestrator
merges results). Across stages, run sequentially (later passes depend
on earlier findings being applied).

### What to skip on a short doc

For a 1–2 page memo:
- Skip Stage 1 (outline contract).
- Skip Stage 3 reverse outline (too short to matter).
- Run Stages 4, 5, and 7 (copy-edit). Skip Stage 6 personas unless the
  reader stakes are high (a memo going to one specific exec is the
  exception — run a single persona-reader call for that one reader).

For anything 3 pages or longer, run the full pipeline.

### Voice samples are optional but high-leverage

The skill works without them. With them, the voice-matcher pass runs
(it requires samples) and the copy-edit handoff is noticeably more
accurate. If the user says they have no samples and have never written
in this register, accept it, skip the voice-matcher in Stage 5, and
proceed. Don't insist.

For repeat users, suggest keeping voice samples in a known location
so they don't re-paste each session. A simple convention:
`~/.claude/voice-samples/<register-name>.md` (e.g.,
`technical-proposals.md`, `internal-memos.md`). At intake, ask the
user if they have stored samples; if yes, read from there. If they
want to save new samples after intake, offer to write them out for
future sessions.

### Honesty about what's invented

If a value gets filled in that the user didn't supply (a hedge replaced
with a specific number, a name swapped in), flag it explicitly: "I
filled in X — confirm before submitting." Never silently invent.

---

## Final check before declaring done

- Reverse outline reads like a coherent argument.
- Promise-payoff: every intro commitment delivered.
- No cannot-invent placeholders left unfilled.
- No category-without-instance flagged in specificity audit.
- No over-explanation to the audience profile.
- Voice-matcher (if run) shows no critical divergences from samples.
- Persona-reader critical gaps and credibility issues addressed or
  acknowledged.
- `human-writer` pass clean.
- `editor` pass returns no critical findings.

If any of these fails, name the failure and loop back to its stage. Do
not declare done with open critical findings.
