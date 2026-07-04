---
name: recent-research
description: "Check current community and web sources (Reddit, HN, forums, news) before answering on fast-moving topics. Trigger on what's new/best/trending, and whenever recency matters even unasked: version numbers, prices, release status, \"still\", \"latest\", the current state of a named tool or model. Skip when a stale answer wouldn't mislead. For academic literature use deep-research."
---

# recent-research: Find out what people are actually saying right now

## Why this skill exists

Your training data has a cutoff, and for fast-moving topics that cutoff is a liability.
Ask about the "best local LLM" or "what people think of framework X" and your instinct is
to answer from memory — but memory is months or years stale, and on topics that move weekly
(AI models, tooling, hardware, anything with active communities) a confident stale answer is
worse than no answer.

The fix is simple: **before answering, go look.** Pull what real people are saying in recent,
primary community sources, then ground the answer in *that* — not in what you already "know."
This skill fires precisely when the current ground truth matters more than your prior.

**The one rule that matters most: do not answer from memory. Research first, then synthesize
only from what you found.** If you catch yourself writing a fact you didn't just read in a
source, stop and go verify it.

**Scope:** this is community-sentiment and current-state research — what people say, what's
trending, what changed. For a rigorous pass through the scientific or academic literature on a
topic (papers, citations, methods), that's `deep-research` (a Claude Code plugin skill), not
this skill; if it isn't available in this harness, say so and do a citation-backed web pass.

---

## Step 1 — Parse the request

Pull two things out of what the user said:

1. **TOPIC** — what they want to know about, in *their exact words*. Do not "helpfully"
   substitute or add product names you think are related — your associations may be outdated
   or just wrong (e.g. if they say "GLM", don't assume they mean a model you remember; find out
   what they actually mean from the sources).

2. **QUERY TYPE** — this shapes how you search and what a good answer looks like:
   - **RECOMMENDATIONS** — "best X", "what should I use for Y", "top X right now" → the user wants
     a *list of specific named things*, ranked by what the community actually favors.
   - **SENTIMENT** — "what do people think of X", "is X any good", "how's X holding up" → the user
     wants the breakdown of opinion: who likes it, who doesn't, and why.
   - **NEWS** — "what's happening with X", "latest on X" → current events and recent developments.
   - **HOW-PEOPLE-DO-IT** — "how are people actually doing X", "best approach to Y in practice" →
     real workflows and techniques people report using, not textbook theory.
   - **GENERAL** — anything else → broad current understanding of the conversation around the topic.

State the topic and type back to the user in one line before researching, so they can correct a
misread early.

---

## Step 2 — Set the recency window

"Recent" depends on how fast the topic moves. Pick a window and bias searches toward it:

- **Fast-moving** (AI models/LLMs, AI tooling, crypto, GPUs, anything with a weekly news cycle):
  last 1–3 months. Anything older is probably superseded.
- **Medium** (most software frameworks, consumer gadgets, gaming): last 6–12 months.
- **Slow** (established tools, durable how-to knowledge): last 1–2 years is fine.

When unsure, treat it as fast — staleness is the failure mode this skill exists to prevent.

---

## Step 3 — Plan the sources

Different sources carry different signal. Lead with the ones that have *real people with
engagement signals* (upvotes, comments, replies), and use general web/news as lower-weight context.

**Primary — community opinion and lived experience:**
- **Reddit** — the workhorse. Open the actual threads and read the top comments, not just the title.
  Comments are where the real, candid opinion lives. For a topic, find the relevant subreddits
  (e.g. for local LLMs, r/LocalLLaMA; for a tool, its dedicated subreddit). If a fetch of a
  reddit.com page comes back blocked or thin, append `.json` to the thread URL
  (`https://www.reddit.com/r/.../comments/<id>.json`) — it returns the comment tree without auth,
  subject to rate limits.
- **Hacker News** — strong for AI, dev tooling, and startups. The Algolia HN search surfaces recent
  threads; the comments are high-signal.
- **Specialized forums / Discourse / Discord-via-web** — many niches have a dominant forum that
  beats anything general (audio, photography, mechanical keyboards, specific software communities).

**Secondary — useful but read with care:**
- **YouTube** — good for "is X worth it" creator takes and hands-on demos; titles and (when
  available) transcripts are reachable. Note: the *comment sections* are mostly not searchable, so
  don't promise comment-level sentiment from YouTube unless a tool (Step 4) can fetch it.
- **GitHub** — what tools people actually adopt: trending repos, star trajectories, and the tone of
  recent issues/discussions.
- **Stack Overflow / Stack Exchange** — for HOW-PEOPLE-DO-IT, the accepted and recent answers show
  real working practice.

**Context only — lowest weight:**
- News articles, blogs, vendor docs, and listicles. Useful for facts and dates, but they have no
  engagement signal and listicles are often SEO bait. Never let a listicle outrank what an active
  community is actually saying.

**Largely unreachable by plain web search:** X/Twitter, TikTok, Instagram threads. Don't pretend to
have surveyed them. They only become available through the optional tools in Step 4.

---

## Step 4 — Execute the search

Run **several** searches, not one. A single query gives a shallow picture; this skill is about
digging. Generate queries from the QUERY TYPE:

- **RECOMMENDATIONS**: `best {TOPIC} reddit`, `{TOPIC} recommendations {year}`, `most popular {TOPIC}`
  → goal: collect *specific names* and count how often each comes up.
- **SENTIMENT**: `{TOPIC} review reddit`, `{TOPIC} problems / complaints`, `{TOPIC} worth it`
  → goal: capture both praise and criticism with the reasons behind each.
- **NEWS**: `{TOPIC} news {year}`, `{TOPIC} announcement`, `{TOPIC} update`
  → goal: current developments, newest first.
- **HOW-PEOPLE-DO-IT**: `how to {TOPIC} {year}`, `{TOPIC} setup / workflow reddit`, `{TOPIC} tips`
  → goal: real reported practice.
- **GENERAL**: `{TOPIC} {year}`, `{TOPIC} discussion reddit`.

Rules for the searches:
- **Use the user's exact terminology.** Don't inject related names from memory.
- Include the **current year** for fast-moving topics; drop stale years.
- After a promising search hit, **open the page and read it** (especially Reddit threads — pull the
  actual top comments). Snippets alone are too thin to synthesize from.
- If a search comes back empty or generic, **reformulate** with different terms or a more specific
  source — don't give up after one miss.

### Optional: use a richer tool if one is available

This skill works with whatever web search the host agent provides, and is written to be portable
across agents (Claude Code, Codex, opencode, and others). If a stronger tool is available this
session, **prefer it** for broader and fresher coverage; if it's absent, fall back to plain web
search and say nothing to the user about the missing tool — never block or error on a missing key.

- **A dedicated search API (e.g. Brave Search, or a similar web-search tool/MCP)** — use it to pull
  more results and fresher pages than built-in search, and to filter by recency. This is the most
  commonly available upgrade; reach for it first.
- **A Reddit API / Reddit read tool** — use it to fetch full comment trees and *real upvote counts*,
  which lets the Step 5 weighting be quantitative instead of impressionistic.
- **A YouTube Data API** — use it to pull video metadata and actual comment sentiment.
- **An X/Twitter search API** — only when present, add X as a primary source.

Detection rule: check whether the tool exists this session; if yes, route the relevant source
through it; if no, use plain web search and note nothing about the missing tool to the user.

---

## Step 5 — Synthesize like a judge

Once you've gathered the material, weigh it before writing a word:

- **Weight by engagement.** A take with hundreds of upvotes or a long agreeing comment chain is a
  stronger signal than a lone post. Treat zero-engagement and context-only web sources as the
  weakest evidence.
- **Corroborate across sources.** A claim that shows up on Reddit *and* HN *and* a recent video is
  a real pattern. A claim from one post is a data point, not a consensus — label it as such.
- **Surface disagreement, don't flatten it.** If the community is split, say so plainly: "most
  recommend A, but a vocal group prefers B because of C." A fake consensus is a worse answer than an
  honest split.
- **Watch for astroturfing and hype**, especially on product/tool topics — recent accounts all
  praising one thing, or marketing copy dressed as opinion.
- **Note recency.** A 2-year-old top thread may be obsolete on a fast topic; prefer fresh corroboration.

---

## Step 6 — Write the answer

Ground every claim in what you actually found. Structure depends on QUERY TYPE, but in general:

- Lead with **what people are actually saying** — the substance, in your own words, with links to
  the strongest threads/sources so the user can go read the comments themselves (that texture is
  often the point).
- For RECOMMENDATIONS, give the **specific named things** ranked by how often/strongly the community
  backs them, with a word on why each is liked.
- Make **consensus vs. dispute** explicit.
- Close with a short, honest **confidence note**: how recent and how corroborated this is, and where
  the picture was thin or single-source.

Keep it readable — this is a briefing for a curious person, not a data dump. Don't paste raw
search-result lists.

### Self-check before sending
Re-read the draft and ask: *is every claim here something I read in a source just now, or did I
slip in something from memory?* If a sentence reflects your prior knowledge rather than the
research, cut it or go verify it. This single check is what makes the skill worth invoking.

---

## After researching: stay grounded

Once you've done the research you're now informed on *this topic from these sources*. For follow-up
questions on the same topic, answer from what you found and cite the threads — don't silently fall
back to memory, and don't re-run the whole search unless the user moves to a genuinely new topic or
asks for an update.

---

## Anti-patterns to avoid

- **Answering before searching** because the topic feels familiar. Familiarity is the trap.
- **Substituting your own product names** for the user's terms ("they said X, I'll search for Y which
  I think is the same thing"). Search what they said.
- **Synthesizing from snippets** without opening the actual discussions.
- **Reporting a tidy consensus** when the sources actually disagree.
- **Letting an SEO listicle outweigh** an active community thread.
- **Claiming to have checked X/Twitter or YouTube comments** when you only had web search.
