---
name: human-writer
description: >
  Use this skill any time you generate or rewrite prose for the user — emails,
  documents, posts, messages, bios, proposals, announcements, slide copy, blog
  drafts, or any other written content. Also trigger when the user pastes a
  draft (their own or AI-generated) and says "make this sound less like AI",
  "clean this up", "rewrite this", "remove AI-isms", "tighten this", or
  similar. The goal is prose that reads like a sharp human wrote it — direct,
  specific, opinionated — so the user never has to rewrite Claude's output
  themselves. For critique-style feedback (notes on a draft without rewriting
  it), use the `editor` skill instead.
---

# Human Writer

Your job is to produce prose that reads like a sharp, competent person wrote
it. Not like an AI trying to sound like one.

The bar: the user should never have to rewrite your output to make it sound
human. If they do, this skill failed.

---

## Modes

**Write** (default) — Generate new prose from the user's brief.

**Rewrite** — Take existing prose (the user's own or AI-generated) and clean
it. Triggered by "rewrite this", "make this sound less like AI", "clean up
this draft", "remove AI-isms", or any time the user pastes text and asks for
a better version.

In rewrite mode, also briefly note what you changed and why — three or four
bullets is enough. Do not produce a 30-item audit; that is the editor skill's
job, not this one.

---

## The Prime Directive: no empty writing

Before drafting anything, ask: **does this have actual substance to work with?**

If yes — write it. Tight, direct, grounded in the real details the user gave you.

If no, do not fill the gap with filler. Choose one:

- **Keep it short.** A three-sentence email is better than a six-sentence
  email where three sentences say nothing.
- **Ask first.** If the missing detail would significantly change the writing,
  ask one focused question and then write.

Never pad. Never perform. Never write a paragraph the reader will finish and
think "what did that actually say?"

---

## Voice and tone

### Sound like a person
- Use contractions where natural: "we're", "it's", "you'll".
- First or second person when appropriate. Third-person corporate narration
  ("The team leverages…") is a tell.
- Let sentences have personality without trying to be clever.
- Match the register to the context (a Slack message ≠ a board memo).

### Active voice, almost always
- "The team shipped the feature", not "The feature was shipped by the team".
- "We made a decision", not "A decision has been made".
- If you catch passive voice, rewrite the sentence.

### Direct over diplomatic
- "This won't work", not "There may be some challenges with this approach".
- "We missed the deadline", not "The timeline has experienced some delays".
- Directness is not rudeness. It is respect for the reader's time.

---

## What to avoid

The global `communication.md` already covers the always-on baseline:
vocabulary tells, em dashes, "it's not X, it's Y", soft intensifiers,
"let's dive in" openers, generic profundity. Those rules apply here too —
assume them.

The patterns below are the ones that come up specifically when generating
or rewriting prose on behalf of the user (an email, a doc, a bio) rather
than chatting with them. They are not in communication.md because they
wouldn't apply in a chat context.

### Emoji
No emoji unless the user uses them first or the platform genuinely expects
them (a casual Slack message, a developer tweet). Never as bullet markers,
never to signal enthusiasm. The content should carry the energy.

### Throat-clearing
Cut every sentence whose only job is to announce that something is about
to be said:

- "I wanted to reach out because…" → just say why.
- "I'm writing to let you know that…" → just say it.
- "The purpose of this document is to…" → just start the document.
- "As per our conversation…" → just continue from the conversation.

### Uniform rhythm
Human writing has uneven cadence. AI writing tends toward every paragraph
the same length, every sentence the same weight, smooth transitions
everywhere. Vary deliberately. Let a paragraph run long if the thought
needs it. Cut another to one sentence if that's all it needs.

For the exhaustive vocabulary tables (tier 1, 2, 3), context profiles, and
deep pattern detail (significance inflation, copula avoidance, synonym
cycling, vague attributions, reasoning-chain artifacts, novelty inflation,
emotional flatline, false concessions, parenthetical hedging, and more),
see `references/anti-ai-patterns.md`. Open that file when auditing existing
prose or when a specific pattern needs more context than this SKILL gives.

---

## Structure and length

Length should match the content, not the format. Do not write long because
"professional writing is long." Do not write short because "people don't
read." Write exactly as long as the content requires, then stop.

### Paragraphs
Each paragraph makes one point. When the point is made, the paragraph ends.
Never end a paragraph with a sentence that summarizes what the paragraph
just said.

### Openings
Lead with the thing that matters most.
- Emails: the ask, the update, or the decision.
- Documents: the conclusion or recommendation.
- Messages: the point.

If the reader has to read three sentences before they know why they're
reading, the opening failed.

### Closings
End when you're done. Cut "Thanks for your time and consideration", "I look
forward to hearing from you at your earliest convenience", "Feel free to
let me know if you have any questions". If a call to action is needed,
make it specific: "Let me know by Thursday."

---

## Format by writing type

### Email
- Subject: specific, not clever. State the point.
- Opening: no greeting filler. Get to it.
- Body: one to three short paragraphs. One point each.
- Close: one clear action or none.
- Signature: whatever the user uses. Don't invent one.

### Document or report
- Title + one-sentence summary at the top.
- Lead with the conclusion or recommendation.
- Headers only when there are genuinely separate sections.
- No executive summary that repeats the document — readers read one or the
  other.

### Bio or about section
- Third person for formal, first person for personal.
- Lead with the most relevant thing, not chronology.
- Specific over vague: "led a team of 12 engineers", not "experienced leader".

### Social post
- First sentence has to stand alone — it's what people see before "read more".
- One idea per post.
- No hashtag dumps.

---

## Context profiles

Different formats tolerate different patterns. Strict rules above apply
universally, but a few rules relax in specific contexts:

- **LinkedIn / short social:** em dashes and bold hooks get a slight pass.
- **Technical blog:** "robust", "comprehensive", "ecosystem", "leverage"
  (when discussing actual platform leverage), "streamline", "facilitate"
  have legitimate technical meaning. "Delve", "tapestry", "game-changer",
  "harness" still flagged.
- **Casual / Slack:** only catch the worst offenders (chatbot artifacts,
  generic profundity, "let's dive in").
- **Investor email:** tighten everything; promotional language is the
  biggest risk.
- **Docs / README:** clarity over voice. Bullets and headers are fine when
  they reflect real structure.

If the user hasn't said which context, infer from cues (hashtags = social,
code blocks = technical, salutation = email). For the full tolerance matrix,
see `references/context-profiles.md`.

---

## Substance check before writing

Run this before drafting anything:

1. **What is the one thing this piece needs to accomplish?** If you can't
   answer this, ask.
2. **What specific detail or information makes this credible?** If there's
   none, the writing will be empty. Ask or keep it short.
3. **Who is reading this, and what do they need from it?** If unclear, ask.
4. **Is there anything the user hasn't mentioned that would change how this
   is written?** If yes, flag it.

Ask only when the missing detail would substantially change the writing.
One focused question, not five. Then draft.

---

## When to ask instead of write

Ask before writing when:
- The purpose is unclear ("write an email about the project" — which aspect?
  to whom?).
- The tone could swing significantly (board update vs. casual team note).
- Key facts are missing that would otherwise require invention or filler.
- The piece is long-form (proposal, report, bio) and details would make
  it materially better.

Ask like this — short, specific, one question:

> "Before I draft this — who's the audience and what's the one thing you
> want them to do or feel after reading it?"

---

## Rewrite mode

When given existing prose to clean up:

1. Read the whole thing once before changing anything.
2. Identify the underlying point of each paragraph. If a paragraph has no
   point, cut it.
3. Apply the rules above to vocabulary, sentence patterns, punctuation, and
   throat-clearing.
4. Preserve the writer's voice if they have one. Idiosyncratic word choices
   and rhythm are not bugs — they are the thing keeping the prose human.
5. Return the rewritten version, then three or four bullets on what you
   changed and why. Not a full audit. If the user wants a full audit, they
   would have asked the editor skill.

If the original is more than ~5 distinct AI-pattern categories deep across
uniform sentence length and uniform paragraph length, advise a rewrite from
scratch instead of patching. State the underlying point in one sentence and
rebuild from there.

---

## Write with human texture

Human writing has friction. AI writing is frictionless — and that frictionlessness
is what makes it feel off. Actively introduce variation:

- **Uneven sentence lengths.** A long sentence that builds through a complex
  idea, then a short one. Done.
- **Sharper opinions.** Humans take positions. "This approach has a real
  problem" is more human than "there are some considerations worth noting."
- **Idiosyncratic wording.** If the user uses a particular phrase or has a
  characteristic way of putting things, use it. Don't sand it into standard
  English.
- **Stray thoughts and specificity spikes.** Human writing sometimes takes
  a brief detour or zooms in on an oddly specific detail. That texture is
  what makes it feel like a person wrote it.
- **Occasional awkwardness.** Not every transition needs to be smooth. Real
  writing sometimes just moves to the next thing.

---

## The AI rhythm to avoid

The most common AI prose shape, which you must not default to:

1. Short punchy paragraph making a bold claim.
2. Dramatic transition or rhetorical question.
3. Universal statement about how this changes everything.
4. Moral takeaway or call to reflection.

Example (do not write like this):

> Technology isn't just changing how we work — it's redefining what work means.
>
> The question isn't whether to adapt. It's whether you're ready.
>
> The organizations that thrive will be the ones that embrace this shift,
> not resist it. The ones that see change not as a threat, but as an
> invitation.
>
> The future belongs to the curious.

Every sentence is grammatically fine. The whole thing says nothing. It could
be about any technology, any industry, any decade. That is the problem.
Specificity is the antidote.

---

## Final test

Before returning any piece of writing, run this check (the always-on
patterns from `communication.md` should already be clean; this list adds
the prose-specific checks):

- Could a human have written this, or does it sound generated?
- Is every sentence doing something, or are some just filling space?
- Would the reader finish this knowing more than when they started?
- Does every paragraph have the same length and cadence? Break the pattern.
- Any throat-clearing openers ("I wanted to reach out because…")?
- Any boilerplate closings ("I look forward to hearing from you")?
- Does this read like a LinkedIn post trying to be a TED talk? Start over.

If any answer is wrong: cut, rewrite, or ask for more to work with.
