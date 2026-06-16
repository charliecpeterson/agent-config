# Optional: a local-model triage pre-pass

This is an optional speed/cost optimization for large reviews when a local model
is available. It does not change what the review concludes — it changes *who does
the cheap part*. Skip it entirely if no local model is running; the review works
without it.

## The pattern (recall → triage → judgment)

The shape the field converged on in 2025–2026 is a two-stage pipeline: a
deterministic scanner produces high-recall, noisy findings, then a model filters
and ranks them before a human (or a stronger model) adjudicates. Splitting it
across two model tiers gives three roles:

1. **Deterministic scanners — recall.** Run the battery from Step 2 broadly and
   noisily: linters with every rule on, `semgrep`/`opengrep`, the dead-code and
   duplication detectors, the contract-trace greps. High recall, many false
   positives. Free, fast, no model.
2. **Local model — triage.** Feed the raw scanner output to a local model
   (Ollama / vLLM endpoint) and have it *cluster duplicates, drop obvious false
   positives, attach a one-line "why this might matter," and rank by likely
   severity*. This is filtering and prioritization, not correctness judgment.
   A mid-size local model is plenty for this; it's the tedious, high-volume part
   that would otherwise burn frontier tokens.
3. **Frontier model (Claude) — judgment.** Only the triaged shortlist reaches
   the expensive model, which does the actual reasoning: is this a real bug, does
   the contract gap matter, what's the fix. Scoped to the shortlist, this is
   cheap precisely because the local model already threw out the chaff.

## The hard rule: never put the local model on judgment

The documented failure of local models in this role is **multi-hop reasoning
across boundaries** — exactly the cross-module contract bugs this skill exists to
catch (a field that's set in one file and silently dropped in another). A local
model will confidently mis-call those. So its job stops at triage: cluster,
filter, rank, annotate. Correctness verdicts and the contract-trace judgment stay
on the frontier model. If you let the local model decide what's a real bug, you
get the systematic over-flagging that makes AI review noise — you didn't save
tokens, you moved them downstream and added false positives.

## Wiring it (concrete)

For Charlie's setup specifically: Nemotron (or any coder model) on the local
4090 via an OpenAI-compatible endpoint (Ollama / vLLM). The triage stage runs
*outside* Claude Code — a small script or a second agent (opencode/crush pointed
at the local endpoint) that reads the scanner output and emits a ranked,
deduped, annotated JSON shortlist to a file. Claude Code then ingests that file
and runs the judgment pass. Keep it a flat file hand-off; don't build a RAG layer
or a long-lived service — for a one-reader workflow that's maintenance you'll
regret, and the orchestration/token-window plumbing is the first thing that
breaks at scale.

When you skip this pre-pass, run the scanners directly in Step 2 and triage them
yourself — the only thing lost is the token savings on a very large finding set.
