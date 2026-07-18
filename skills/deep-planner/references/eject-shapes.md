# Eject shapes: focused tasks and prioritized roadmap

Loaded by `../SKILL.md` at the Eject Check when the session shape is
*focused tasks* or *prioritized roadmap*. Both shapes write directly into
`PROJECT_PLAN.md` and end the session. (The third shape,
decision-mapping, has its own file: `references/decision-mapping.md`.)

## If focused tasks: eject to task-list output

Write the focused work directly into `PROJECT_PLAN.md` and end the
session. Reuse the template; most mid-pipeline sections stay empty.

- **Goal, Archetype, Scope, Deadline, Expertise calibration**:
  already filled in from Phase 0.
- **Decision Log**: append a single entry: choice =
  "focused-tasks mode," reasoning = one line on why, revisit-if =
  condition that would warrant a re-plan.
- **Roadmap**: repurpose as a checkbox task list with the
  user-confirmed focused work. Use `- [ ]` syntax. Group by
  thread if the user named multiple (e.g., "Cleanup," "Security
  pass," "TUI").
- **Deferred Register, Open Questions**: fill in as appropriate.
- **Research Summary, Production-Readiness Audit, Architecture**:
  omit entirely. Don't include empty headings.
- **Dependencies & Risks**: anything relevant.

Summarize the task list briefly and end.

## If prioritized roadmap: eject to ranked-roadmap output

Write a ranked, sequenced gap roadmap into `PROJECT_PLAN.md` and
end the session. Shape:

- **Goal, Archetype, Scope, Deadline, Expertise calibration**:
  from Phase 0.
- **Decision Log**: a single entry noting "prioritized-roadmap
  mode" plus any sequencing decisions confirmed with the user
  (e.g., "distribution-first vs. quick-win first").
- **Gap Inventory** (new section, insert before Roadmap): findings
  from the bounded codebase orientation, grouped by theme. Each
  finding names the gap concretely (what's missing, what's
  stubbed, what's partial) but not how to fix it.
- **Roadmap**: phased plan with rationale. For each phase:
  - Name and one-line identity ("Phase 1: installable and
    trustworthy" / "Phase 2: cheap analysis wins" etc.).
  - What's in this phase (concrete items, `- [ ]` checkboxes).
  - **Why it's at this position in the sequence** (one or two
    lines: gates downstream work / cheap-high-visibility win /
    builds momentum / deferred per appetite).
  - Rough effort framing (days / weeks / sustained).
  - What this phase explicitly defers to a later phase.
- **Deferred Register**: items intentionally deferred past the
  last phase (force field rewrites, large refactors, etc.).
- **Open Questions**: any genuine forks the user wanted to revisit.
- **Research Summary, Production-Readiness Audit, Architecture**:
  omit. Not relevant to a gap-ranking session.
- **Dependencies & Risks**: anything that could derail sequencing.

The ranking principle: impact-for-stated-audience divided by
effort, with the user's stated build appetite as the tiebreaker.
Surface the principle and the resulting order to the user before
writing; let them reorder.

Summarize the roadmap briefly and end.
