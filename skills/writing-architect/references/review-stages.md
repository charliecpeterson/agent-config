# Review stages (3–6) protocol

Loaded by `../SKILL.md` when entering Stage 3; stays in context through
Stage 6. Each pass dispatches sub-agents in `~/.claude/agents/` so the
review runs in an isolated context, returns JSON with a known schema,
and the conductor synthesizes findings for the user. If a sub-agent
returns `{"error": "missing_input", ...}`, gather what it needs and
re-invoke; never fall back to running the pass inline.

## Stage 3: Developmental review

Run this once the full draft exists. Macro only. **Dispatch the
`developmental-reviewer` sub-agent** via the Agent tool — do not run
this pass inline in your own context. Context isolation is the point;
if you do it inline, sentence-level concerns bleed into a job that
should only see structure.

Invocation:

```
Agent({
  description: "Developmental review of draft",
  subagent_type: "developmental-reviewer",
  prompt: <self-contained prompt including draft path, audience profile,
           outline, document type. Sub-agent has its own context — give
           it everything it needs in one shot.>
})
```

The sub-agent returns a strict JSON object with five fields:
`reverse_outline`, `alignment_issues`, `missing_sections`,
`argument_flow`, `claims`. See `agents/developmental-reviewer.md` for
the schema.

Your job once it returns:

1. **Show the reverse outline to the user first.** This is the
   highest-leverage single artifact. Ask: "Does this sequence read like
   a coherent argument? Anything missing, redundant, or out of place?"
2. **Then present alignment issues, missing sections, argument-flow
   breaks** — tiered by severity. Hand-waved claims go in a separate
   pile.
3. **Wait for user direction.** They tell you which to fix, which to
   leave. Apply the structural changes they approve.
4. **Do not proceed to Stage 4 until structural changes are applied.**
   A structural change can invalidate every later finding.

## Stage 4: Structural review

After the user has acted on the developmental findings. **Dispatch the
`structural-reviewer` sub-agent.**

Invocation:

```
Agent({
  description: "Structural review of draft",
  subagent_type: "structural-reviewer",
  prompt: <self-contained: draft path, outline, optionally the
           developmental-reviewer's reverse outline from Stage 3.>
})
```

The sub-agent returns JSON with `section_spine`, `spine_breaks`,
`promise_payoff`, and a flat `findings` list (each finding tiered as
critical / important / minor). See `agents/structural-reviewer.md` for
the schema.

Present findings tiered. Critical findings need user direction before
proceeding. Important and minor can be batched. Wait for user direction
before Stage 5.

## Stage 5: Specificity audit and voice match (parallel)

Two passes run together, in parallel, because they're independent
and answer different questions:

- **Specificity audit** catches outsider-voice patterns (categories
  without instances, methods without parameters, over-explanation,
  hedging on countables). The pass tuned to the failure mode this
  skill exists for.
- **Voice match** catches "this isn't how the user actually writes"
  patterns by comparing against their published samples.

The specificity-auditor needs the audience profile and cannot-invent
list. The voice-matcher needs the voice samples from intake. If
either is missing, gather first or skip that pass and tell the user.

Dispatch both in one message via two parallel Agent calls:

```
Agent({
  description: "Specificity audit for outsider voice",
  subagent_type: "specificity-auditor",
  prompt: <self-contained: draft path, full audience profile,
           full cannot-invent list.>
})
Agent({
  description: "Voice match against user samples",
  subagent_type: "voice-matcher",
  prompt: <self-contained: draft path, voice samples (inline),
           audience profile context.>
})
```

The specificity-auditor returns:
- `fix_able` — findings the skill can act on without inventing domain
  commitments. Each entry includes `suggested_fix` as the actual
  replacement text.
- `requires_user` — findings that need a real domain value from the
  user. Each entry includes `question_for_user` and which cannot-invent
  item it maps to.

The voice-matcher returns:
- `sample_profile` — the user's voice characterized along four axes
  (vocabulary register, sentence rhythm, specificity habits, voice
  markers). Useful to show the user as a sanity check.
- `divergences` — per-paragraph flags where the draft drifts from the
  sample profile, with the specific axis and (where possible) a
  rephrase drawn from the samples.

See `agents/specificity-auditor.md` and `agents/voice-matcher.md` for
full schemas.

Your job once both return (the two reports have different schemas —
don't literally merge them; coordinate them):

1. **Collapse duplicates across the two reports** before presenting.
   When a specificity finding and a voice divergence point at the same
   paragraph or sentence, present them as one finding so the user sees
   each problem once. Everything else stays in its own list.
2. **Batch all `requires_user` questions** from specificity into one
   message. Don't ask them one at a time — they came up in one pass,
   answer them in one pass. A voice divergence whose rephrase depends
   on one of those answers is provisional: get the domain value first,
   then generate the rephrase.
3. **Present `fix_able` and voice `divergences` together** as a list of
   proposed changes. Let the user accept all, reject some, or edit
   individually.
4. **Apply approved fixes and user-supplied answers** to the draft.
   Anything the user can't supply right now becomes a placeholder, not
   an invented value.

If voice samples were not provided at intake, run only the
specificity-auditor and skip the voice-matcher. Note that to the user
so they know voice was not checked.

If both passes return near-zero findings, the draft is either already
specialist-grade or the inputs are too lenient. Sanity-check by asking
the user if the draft now reads like a peer wrote it.

## Stage 6: Persona-reader simulation

After the draft has been structurally and specificity-corrected, read
it through the eyes of its actual audience segments. This catches
reader-experience problems the prior passes can't see — what feels
thin, what reads as posturing, what's missing for *this* reader even
though the document is structurally complete.

**Dispatch one `persona-reader` sub-agent per audience segment, in
parallel.** For a typical grant proposal, that's two or three
personas: the technical reviewer, the panel chair, the program officer.
For a paper: the conservative referee, the enthusiastic referee, the
journal editor. For a memo: the recipient, anyone else copied who
might intervene.

**Load `references/persona-library.md`** to find a starting-point
persona for each audience segment. The library covers common readers:
grant panel reviewer (ACCESS/NSF/DOE), NIH study section reviewer,
journal referee (conservative and enthusiastic variants), conference
reviewer, program officer, executive on a memo, lay reader. Each
entry includes role, expertise, what they're scored on, how they
read, and what trips their skepticism.

Pick the library persona that matches each segment and adapt it to
the specific context — name the field, the venue, the agency, the
person if known. If a segment isn't in the library, build the persona
from scratch using the framework at the top of that file. A usable
persona spec needs all of:
- Role / job title
- Domain expertise (what they know cold)
- What they are scored on
- How they read in this context (skim vs. deep, rubric-based?)
- What they've seen before
- What trips their skepticism

If the audience profile from intake isn't specific enough to
construct two or three distinct personas, ask the user before
dispatching. A generic "the panel" is not a usable spec.

Dispatch in parallel:

```
Agent({
  description: "Persona read: technical reviewer",
  subagent_type: "persona-reader",
  prompt: <self-contained: draft path, persona spec for technical
           reviewer, audience profile context.>
})
Agent({
  description: "Persona read: panel chair",
  subagent_type: "persona-reader",
  prompt: <self-contained: draft path, persona spec for panel chair,
           audience profile context.>
})
```

Each agent returns six dimensions per persona: initial reaction, what
works, critical gaps, credibility issues, missing examples, one
critical fix. See `agents/persona-reader.md` for the schema.

Your job once they return:

1. **Synthesize across personas.** Where multiple personas flag the
   same issue, surface it once with high priority. Where personas
   diverge (one praises, another panics), surface the divergence
   directly — it usually means the doc is calibrated for one segment
   at the expense of another, and the user needs to decide.
2. **Highlight each persona's `one_critical_fix`** even if it didn't
   appear elsewhere. That field is the persona's highest-leverage ask.
3. **Wait for user direction.** Critical gaps and credibility issues
   often loop back to Stage 3 or Stage 5; cosmetic fixes can proceed
   to Stage 7.

If the personas converge on critical issues, recommend looping back
to Stage 3 before proceeding to copy-edit. A structurally-thin
proposal does not benefit from a tighter copy edit.
