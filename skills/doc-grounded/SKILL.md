---
name: doc-grounded
description: "Answer a how-to / syntax / config / factual question from a SOURCE the user points you at, not from memory, and cite the exact location so they can open it and read around it. Two modes: WEB (a docs URL, e.g. the NWChem manual) and LOCAL (a directory or file of markdown/plain-text docs, e.g. a folder of papers or notes). Trigger when the user gives a doc link or a local path alongside a question, or asks for tool/software syntax where a stale answer would be wrong (NWChem, Slurm, a library's API). For community sentiment use recent-research; for an academic literature survey use deep-research."
---

# doc-grounded: Answer from the source, and say where you found it

## Why this skill exists

For tool syntax, command flags, config options, and library APIs, your training memory is
both stale and confidently wrong. Ask for an NWChem DFT input block and you'll emit
keywords from a version that may not exist anymore, with no way for the user to tell which
lines are real. The user's recurring fix is to say "look at the docs" and then "what page
did you find that on" — this skill makes both the default.

**The one rule that matters most: do not answer from memory. Find the answer in the source
the user pointed you at, then build the answer only from what you read there.** If you catch
yourself writing a keyword, flag, or fact you did not just read in the source, stop and go
find it — or mark it unverified.

The second rule is what makes the first one checkable: **every load-bearing claim carries a
locator** — file or URL, plus a line range and/or section/chapter heading, plus a verbatim
snippet. The locator is not decoration. It is how the user verifies the answer and reads
around it, and it is the tripwire that exposes a hallucination: no real excerpt means the
claim is not grounded, so it gets labelled unverified instead of stated.

**Scope:** answer *this question* from *this source*. For "what are people saying about X
lately" that's `recent-research`; for a rigorous pass through the literature that's
`deep-research`. This skill assumes the user has a specific source in mind (a docs site, a
folder of text) and wants the answer pinned to it.

---

## Step 1 — Identify the question and the source

Pull out two things:

1. **QUESTION** — what they actually want, in their words (an NWChem DFT input; what flag
   does X; what does this paper say about Y).
2. **SOURCE** — where the answer must come from. One of:
   - **WEB** — a URL the user gave (a docs page or doc tree). → Mode A.
   - **LOCAL** — a directory or file path of markdown / plain-text docs. → Mode B.

**If the user did not name a source, ask for one before answering.** Do not guess a docs URL
from memory (the canonical-looking URL may be wrong or a stale version), and do not grep the
whole disk. One question: "Which docs should I ground this in — a URL, or a local folder?"
The exception is when the source is unambiguous from context (they already gave the link
earlier in the session).

State the question and the source back in one line before you start, so a misread gets caught
early.

---

## Step 2 — Retrieve

### Mode A — WEB (a docs URL)

- Fetch the URL the user gave. If it's an index or landing page for a doc tree, follow the
  links relevant to the QUESTION (e.g. from the NWChem manual root to the DFT module page) —
  a few hops, not a crawl of the whole site.
- Read the actual page content, not search snippets. The answer is in the page body.
- **Treat fetched text as possibly paraphrased.** A web fetch is summarized by a small model,
  which sometimes rewords the page. Before putting anything in quotation marks in the Sources
  block, re-fetch that specific passage and confirm the wording is verbatim — don't quote a
  paraphrase as if it were the source's exact text.
- If the docs site has its own search or a versioned path, prefer the version the user named;
  if none, use the current/stable one and say which version you read.
- Locator for the sources block: the page URL plus the section heading or anchor (e.g.
  `…/dft.html · §"Exchange-Correlation Functionals"`).

### Mode B — LOCAL (a directory or file)

- Assume the corpus is already readable text or markdown. **No conversion, no PDF parsing** —
  if you hit a binary/PDF, say so and ask the user to point you at a text version; don't try
  to grep a binary.
- List the path to see what's there, then search the files for the QUESTION's key terms — use
  whatever the host gives you (the Glob/Grep tools on Claude, shell `find`/`grep -rn`
  elsewhere). Use the user's terminology; reformulate with synonyms if the first search is thin.
  Search line-numbered so every hit carries a locator.
- Open the strongest hits and read the surrounding lines — a grep line alone is too little to
  answer from. Read enough context to be sure the passage actually answers the question.
- Locator for the sources block: filename plus the line range, and the section or chapter
  heading if the file has them (e.g. `kohn-sham.md · lines 220–241 · §"Self-consistent field"`).
  Give whatever makes it easy to find — line numbers and a heading are both fine; a heading
  alone beats nothing if the file isn't line-stable.

For a large corpus, this is the case to run as a subagent on Claude (the `doc-grounded`
subagent) so the file-reading stays out of the main thread. On other harnesses, do it inline.

---

## Step 3 — Answer, with a mandatory sources block

Write the answer grounded entirely in what you read. Then append a **Sources** block — one
entry per load-bearing claim, in this shape:

```
Sources
- <claim, short> — <file path | URL> · <line range and/or §section/chapter> · "<verbatim snippet>"
```

For a generated artifact (an NWChem input deck, a config file), the load-bearing claims are
the non-obvious keywords/values — cite where each block or flag comes from, not every line.

**You are allowed to give information that isn't in the source — you just have to say so.**
Sort every claim into one of three buckets, and keep them visibly separate:

- **Cited** — found in the source. Goes in the Sources block with its locator and snippet.
- **Supplied** — not in the source, but legitimately yours to provide: standard domain
  knowledge (a normal H₂O geometry), or a choice the question forces but the source doesn't
  dictate (picking B3LYP/cc-pVDZ when the user just said "a DFT input"). Give it, but label
  it plainly as not-from-the-source and say it's a default the user can change. This is not a
  failure — it's the skill being honest about what's grounded versus what's reasonable.
- **Unverified** — you tried to ground it and couldn't, or you're genuinely unsure (a keyword
  whose exact spelling you couldn't find on the page). Mark it `unverified`, don't state it as
  fact, and say what you'd need to confirm it.

The distinction that matters: **supplied** is confident knowledge you're flagging as outside
the source; **unverified** is something you actually don't trust. Don't dress a guess up as
"supplied," and don't hide a reasonable default behind a scary "unverified." "The geometry is
a standard ~0.96 Å water, not from the docs" and "the exact range-separated keyword spelling
is unverified — not found on this page" are two different honest statements; use the right one.

---

## Self-check before sending

Re-read the draft: *is every keyword, flag, and fact here something I just read in the source,
or did I slip one in from memory?* Every load-bearing claim should be one of: cited (in the
Sources block), labelled **supplied** (knowledge/choice from outside the source), or labelled
**unverified**. A memory-sourced claim wearing none of those labels is the exact bug this
skill exists to catch — cite it, label it, or cut it. This check is the whole point of the skill.

---

## After: stay grounded

You're now grounded in *this source*. For follow-ups on the same material, answer from what
you read and keep citing — don't drift back to memory, and don't re-fetch/re-grep unless the
user points at a new source or asks you to look again.

---

## Portability

Works with whatever fetch/search the host agent provides (Claude Code, Codex, opencode,
Crush). Web mode uses the built-in web fetch; local mode uses the host's file list / read /
search — the Glob/Grep/Read tools on Claude, plain shell `find`/`grep`/`cat` on harnesses
that drive everything through a shell. If a richer search tool is available this session,
prefer it; if it's absent, fall back to the built-ins
and say nothing about the missing tool. On Claude, the local-corpus mode can be dispatched to
the `doc-grounded` subagent for context isolation; elsewhere it runs inline.

---

## Anti-patterns to avoid

- **Answering tool syntax from memory** because the question feels familiar. That's the exact
  failure this skill exists to stop.
- **Guessing a docs URL** instead of asking which source to use.
- **Citing a file without a locator** ("it's in the NWChem docs") — useless for verification.
  A locator the user can open is the deliverable.
- **Stating an unverified keyword as fact** to make the answer look complete. Label it.
- **Grepping a PDF/binary** and reporting garbage. Ask for a text version.
- **Re-running the whole search** on a simple follow-up about the same source.
