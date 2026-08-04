---
name: session-audit
description: "Independent re-verification of an AI session's recorded work: extract the falsifiable claims from commit messages, lab logs, and boards since a git ref, fan out FRESH-context workers to re-derive them (never trusting the session's own verification), report CONFIRMED/REFUTED/UNVERIFIABLE, and convert findings into executable gates. Trigger on 'audit the session', 'check the AI's work', 'verify recent claims', 'is the work on the right path', or at milestones — before a family-wide submit, a release gate, or after producer-code changes. NOT a codebase health verdict (code-review-deep), not doc-vs-code drift (doc-sync), not a latent-bug hunt (bug-scan): this audits what the session CLAIMED against what IS."
---

# Session Audit

Working sessions accumulate two kinds of error that the session itself
cannot see: claims whose verification was itself buggy, and narratives
that anchor every subsequent judgment. This skill is the counter-party —
a cold reader that re-derives instead of re-reads.

Distilled from one week of an ECP-fitting campaign where independent
fresh-context review caught, among others: an equality test in a
just-written safety guard that should have been a prefix test; a project
board still calling a phase complete two supersessions after the lab log
had retired it; 93 shipped artifacts whose validity could not be
established by inspection; and a mass job kill the working session spent
a day mis-attributing to the filesystem when `git reflog` next to `sacct`
answered it in one minute. In the same week, the working session's *own
verification scripts* were wrong three times — a comparison against the
wrong baseline, an audit whose rules misread two data conventions as 99
defects, a parser that read `5f16d17s2` as f¹⁶. The lesson under all of
it: the check must be independent in both context and mechanism.

## Boundaries

- **vs `code-review-deep`**: that renders a health verdict on the code
  itself. This audits the *session's account* of the work — the claims,
  the board, the guards — against reality. A healthy repo can still
  carry a false claim ("all callers converted") and a stale board.
- **vs `doc-sync`**: that checks docs against code systematically. This
  samples *claims* (many of which live in commit messages and logs, not
  docs) and re-derives them. Findings about stale prose get handed to
  doc-sync's territory; findings about false verification do not exist
  there.
- **vs `bug-scan`**: that hunts defects nobody mentioned. This starts
  from what WAS mentioned — the session's assertions — and tests them.
  Run bug-scan when you distrust the code; run this when you distrust
  the narrative.

## The cardinal rule: independence

**Never run this as a fork or continuation of the session being
audited.** A fork inherits the session's context and therefore its
anchoring — it will find the OST theory plausible because the session
believed it. Workers get the repo, the claim, and nothing of the
session's reasoning.

Independence of *mechanism* matters as much as context: a worker must
not verify a claim by re-running the session's verification script and
nodding. Either read that script adversarially for bugs, or write an
independent check. Three of the week's worst misses were verification
scripts confirming their own assumptions.

## Process

### 0 — Scope to a window, at a milestone

Take a git ref range (`<ref>..HEAD`) or a date window, plus the
session-artifact sources: commit messages, the project's append-only
log if it has one, the task board, PR descriptions. Run at decision
points — before a big compute submit, before a release gate, after
changes to producer code — not on a timer. A periodic audit of an idle
repo is token spend that confirms nothing happened.

### 1 — Extract the falsifiable claims

Sweep the window's artifacts for assertions that can be wrong, and tag
each with its shape:

- **counts** — "124/124 match", "29 of 31 completed"
- **exactness** — "byte-identical", "exactly zero on all 30", "sub-µHa"
- **selectivity** — "rejects exactly the six bad files, accepts 84"
- **completeness** — "all callers converted", "no D2h remains", "every
  consumer updated"
- **negative claims** — "nothing else touched", "unaffected by X"
- **causal claims** — "the failure was caused by Y" (check the boring
  coordination layer — git reflog, cron, operator actions — before any
  exotic infrastructure theory; timestamps decide, not plausibility)

Completeness and negative claims are the highest-yield: they are cheap
to assert, expensive to make true, and the session had the least
evidence for them. Sweep those exhaustively; sample the rest, weighted
by blast radius (what downstream work believes this claim?).

### 2 — Fan out fresh workers to re-derive

One brief per claim or claim-cluster, to `code-skeptic` (adversarial,
evidence-required) or `general-purpose` (when re-derivation needs to
run code). Every brief carries:

- the claim, verbatim, with its source (commit sha / log entry)
- where to look, but NOT the session's reasoning or conclusions
- the instruction: *re-derive by independent means; if the session
  left a verification script, audit the script rather than rerunning
  it; report file:line evidence or the exact command and output*
- the standing rule: findings without evidence are discarded

### 3 — Sweep the consistency layer

Alongside claim checks, three mechanical passes that need no sampling:

- **board vs log vs tree**: does the project's live board agree with
  its append-only record and with the artifacts on disk? (The commonest
  drift: the log is truth, the board is decoration.)
- **fresh guards, adversarial read**: any safety check, gate, or guard
  added in the window gets read for what its pattern *misses* — the
  equality-vs-prefix class. New guards are written to pass the incident
  that motivated them; test them against the neighbor incident.
- **provenance by inspection**: pick N shipped artifacts at random and
  determine, from their content alone, whether they are current. If
  that requires archaeology, that is a finding.

### 4 — Report: CONFIRMED / REFUTED / UNVERIFIABLE

Rank by blast radius, refuted first. A refuted claim carries the
correct value, the evidence, and the list of downstream decisions that
believed it. UNVERIFIABLE is an honest verdict, not a failure — but
recurring unverifiables indicate the session is asserting things it
never measured, which is itself a top-line finding.

Do not pad with praise. Do not report style nits — this skill audits
truth, not taste. Where a recommendation would be heavier than the
failure mode it prevents, say so and mark it optional; checkers that
over-prescribe get ignored.

### 5 — Mechanize the findings

Every confirmed-important claim and every expensive re-check ends with
a proposal: the script, assertion, or manifest field that makes the
next LLM re-check unnecessary. The deliverable's last section is
"gates to add", and the measure of a good audit series is that it
shrinks — properties move from sampled-by-agent to enforced-by-code.
The auditor's job is to find what is not yet mechanized, not to become
the mechanism.

## Honest limits

State these in the report header. The auditor shares the species'
failure modes: it can be confidently wrong, it will hedge on deep
domain judgment, and its own checks can be buggy — evidence discipline
is the mitigation, not a cure. Domain-content calls (is this physics
right? is this the correct method?) are flagged as questions for the
human, never adjudicated by the audit.
