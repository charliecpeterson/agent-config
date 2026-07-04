---
name: llm-council
description: "Run a real decision through a council of five AI advisors who each analyze it from a different thinking lens, peer-review each other anonymously, and synthesize a single verdict. Adapted from Karpathy's LLM Council. MANDATORY TRIGGERS: 'council this', 'run the council', 'pressure-test this', 'stress-test this', 'war room this', 'debate this'. STRONG TRIGGERS when paired with a genuine decision and a real tradeoff: 'should I X or Y', 'which option', 'is this the right move', 'I'm torn between', 'validate this', 'get multiple perspectives'. Do NOT trigger on factual lookups, simple yes/no questions, creation tasks ('write me X'), or a casual 'should I' with no real stakes. DO trigger when the user brings a decision with stakes, multiple options, and context that wants pressure-testing from several angles. Claude Code only — it spawns sub-agents."
---

# LLM Council

Ask one model a question and you get one answer. It might be sharp, it
might be mid, and you can't tell which because you only saw one
perspective. The council fixes that: it runs the decision through five
independent advisors, each thinking from a different angle, has them
review each other anonymously, then a chairman synthesizes where they
agree, where they clash, and what you should actually do.

This is adapted from Andrej Karpathy's LLM Council. He dispatches a
query to several different models, has them peer-review each other
anonymously, then a chairman writes the final answer. We do the same
thing inside Claude using sub-agents with different thinking lenses
instead of different models — the `council-advisor` agent, fired five
times in parallel.

## When to run the council

For decisions where being wrong is expensive and there's genuine
uncertainty. Good council questions: "Rewrite the slow MCP server in
Rust or keep optimizing the Python?", "Which of these three paper
framings is strongest?", "Should I move the group off environment
modules to containers — am I crazy?", "Buy a second GPU box or lean on
the ACCESS allocations?", "Here's my proposal's aims page, what's weak?"

Not for the council: factual lookups (one right answer), creation tasks
("write me a tweet"), processing tasks ("summarize this"), or a decision
you've already made and just want validated — the council will tell you
things you don't want to hear, which is the point. If the user asks
something with one right answer, just answer it.

## The five lenses

Five thinking styles, chosen because they create tension with each
other rather than five flavors of the same take. The full descriptions
live in the `council-advisor` agent; in short:

- **The Contrarian** — what's wrong, missing, about to fail.
- **First Principles** — what are we actually solving; is this even the
  right question.
- **The Expansionist** — the upside everyone's missing.
- **The Outsider** — zero context, reacts only to what's on the page,
  catches the curse of knowledge.
- **The Executor** — can it be done, what's the Monday-morning first
  step.

The tensions are the value: Contrarian vs. Expansionist (downside vs.
upside), First Principles vs. Executor (rethink vs. just ship), with
the Outsider keeping everyone honest.

## How a session works

### Step 1 — Gather context, then frame the question

The user's question is usually the tip of the iceberg, and their
workspace holds context that turns generic advice into specific advice.
Before framing, spend ~30 seconds (no more) with `Glob`/`Read` looking
for the two or three files that matter for *this* question:

- `CLAUDE.md` / project root context (constraints, stage, preferences)
- a `memory/` folder (audience, past decisions, business details)
- anything the user referenced or attached
- prior council transcripts in `~/scratch/llm-council/` (don't
  re-council the same ground)
- question-specific files (asking about pricing? look for past launch
  numbers, revenue, audience research)

Then write a **framed brief**: a neutral, self-contained statement that
every advisor will receive. Include the core decision, the key context
from the message *and* the workspace, and what's at stake. Don't add
your own opinion or steer it — but make the brief rich enough that an
advisor can be specific instead of generic. The advisors get *only*
this brief (the Outsider depends on that), so anything they need has to
be in it.

If the question is too vague to frame ("council this: my business"),
ask exactly one clarifying question, then proceed.

### Step 2 — Convene the council (5 advisors, parallel)

Spawn five `council-advisor` agents **in one message so they run in
parallel** — sequential spawning wastes time and risks earlier takes
bleeding into later ones. Each gets the framed brief and one lens spec.
Each returns a 150-300 word independent take.

### Step 3 — Peer review (5 reviewers, parallel)

This is the step that makes it more than "ask five times." Collect the
five takes and **anonymize** them as Response A-E, randomizing which
advisor maps to which letter so there's no positional or lens bias.

Spawn five reviewers in parallel (use the `general-purpose` agent type —
this round is lens-agnostic), each seeing all five anonymized responses
and answering three questions:

```
You are reviewing the outputs of an LLM Council. Five advisors
independently answered this question:

---
[framed brief]
---

Anonymized responses:

**Response A:**
[take]
**Response B:**
[take]
**Response C:**
[take]
**Response D:**
[take]
**Response E:**
[take]

Answer these, referencing responses by letter. Under 200 words, direct:
1. Which response is strongest? Why?
2. Which has the biggest blind spot? What is it missing?
3. What did ALL five miss that the council should consider?
```

### Step 4 — Chairman synthesis

You (the orchestrator) are the chairman. You have everything: the
brief, the five takes de-anonymized so you can see which lens said
what, and the five peer reviews. Write the verdict in this structure:

```
## Where the Council Agrees
Points multiple advisors converged on independently. High-confidence signals.

## Where the Council Clashes
The genuine disagreements. Present both sides, explain why reasonable
advisors disagree. Don't smooth them over.

## Blind Spots the Council Caught
Things that only surfaced in peer review — one advisor missed it,
another flagged it.

## The Recommendation
A clear, direct call. Not "it depends." You may side with a lone
dissenter over the majority if their reasoning is strongest — say why.

## The One Thing to Do First
A single concrete next step. One thing, not a list.
```

### Step 5 — Write the artifacts

Save both files to `~/scratch/llm-council/` (per my scratch convention —
keeps council output out of whatever repo I'm in). Get the timestamp
from the shell: `date +%Y%m%d-%H%M%S`.

```
~/scratch/llm-council/council-<timestamp>.html   # visual briefing
~/scratch/llm-council/council-<timestamp>.md      # full transcript
```

`mkdir -p ~/scratch/llm-council` first. The **HTML** is a single
self-contained file (inline CSS, system font stack, white background,
subtle borders, soft accent colors — a clean briefing, nothing flashy):
the framed question at top, the chairman's verdict prominent (most
people read only this), a simple visual of where advisors aligned vs.
diverged, then collapsible sections (collapsed by default) for each
full advisor take and the peer-review highlights. The **markdown
transcript** is the archive: original question, framed brief, all five
takes, all five reviews with the anonymization mapping revealed, and
the full synthesis. Open the HTML when done: `open <file>` on macOS.

In chat, give the user the verdict directly and the path to both files.
Don't make them open the HTML to learn the outcome.

## Example

**User:** "Council this: I maintain a dozen personal MCP servers as
separate repos and keep re-fixing the same launch/config/env plumbing
in each. I'm thinking of consolidating them into one monorepo with
shared infrastructure. Right move?"

The five takes diverge hard. The Contrarian: a monorepo couples
release cycles — one broken dependency bump takes down every server at
once, and for a solo maintainer the migration is a tax paid up front
for benefits that mostly never arrive. First Principles: the stated
problem is duplicated plumbing, not repo count — extract the shared
launch/config layer into one small library the twelve repos depend on,
and the monorepo question dissolves. The Expansionist: the shared
layer is the interesting asset — packaged well, it's the MCP scaffold
other people are missing; publish it. The Outsider: "I can't tell what
any of these servers do from their names — whatever you pick, the real
problem is that nothing lists what exists and what's running." The
Executor: don't migrate twelve at once; port two servers onto the
shared layer this weekend and see if the plumbing actually unifies.

**Chairman's verdict:** don't build the monorepo. The duplication is
real but it lives in the plumbing, not the repo layout (First
Principles' reframe, which the Contrarian's coupling argument
independently supports, is the highest-leverage insight). Extract the
shared library, pilot it on two servers per the Executor, and steal
the Outsider's point: add a one-page registry of what exists. Revisit
consolidation only if the library doesn't kill the re-fixing.

## Notes

- Always spawn the five advisors in parallel, always anonymize before
  peer review — if reviewers know which lens said what, they defer to
  styles instead of judging on merit.
- The chairman can overrule the majority when the dissenter's reasoning
  is stronger. Say so explicitly.
- Don't council trivial questions. The council is for genuine
  uncertainty where multiple angles actually add value.

---

Methodology by [Andrej Karpathy](https://x.com/karpathy). Claude Code
skill by [@tenfoldmarc](https://github.com/tenfoldmarc/llm-council-skill),
adapted here to the council-advisor sub-agent split.
