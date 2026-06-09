# Project CLAUDE.md template

Write the new project's `CLAUDE.md` from this shape. Fill every section with
the real values; delete a section rather than leaving a placeholder. Keep the
whole file under ~40 lines — global rules already cover style, communication,
and engineering judgment, so repeat none of that here.

```markdown
# <name>

<One or two sentences: what this is and who/what it's for.>

## Commands

- Test: `<command>`
- Lint: `<command>`
- Run: `<command>`

## Layout

- `src/<pkg>/` — <what lives here>
- `tests/` — <test style, how to run one test>
<only directories that exist and need explaining>

## Conventions

<Only project-specific rules: domain constraints, invariants, things a
fresh session would get wrong. Not general style — that's global.>

## Don't touch

<Generated files, data directories, vendored code — if any.>
```
