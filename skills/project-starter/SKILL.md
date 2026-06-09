---
name: project-starter
description: "Bootstrap a new project with my conventions so it never starts as a blank slate. Trigger on \"new project\", \"start a repo\", \"scaffold this\", \"set up a project\", or picking a name for something about to be built. Picks the matching template (Python science/ML, Rust CLI, TypeScript tool, MCP server), lays out the skeleton, and writes a project CLAUDE.md."
---

# project-starter

Bootstrap a new repo the way I'd build it, so the first session in it starts
with structure and conventions instead of an empty directory.

## Workflow

1. **Gather the three facts** (ask only for what's missing, one short batch):
   - Name and one-line purpose.
   - Project type: `python-science`, `rust-cli`, `typescript-tool`, or
     `mcp-server`. Infer from context when obvious.
   - Public (MIT, like my other repos) or private/unlicensed.

2. **Read the matching template** in `templates/` next to this file. It
   defines the layout, the init commands, and the starting dependencies.
   Templates are guides, not file dumps — instantiate them with the real
   project name and purpose.

3. **Scaffold**:
   - `git init` (branch `main`).
   - Run the template's init commands (`uv init`, `cargo new`, `npm init`…).
   - Create the layout the template describes. Nothing speculative: no empty
     placeholder modules, no "TODO: implement" stubs, no CI until there's
     something to run in CI.
   - Write the project `CLAUDE.md` from `templates/claude-md.md`, filled in
     with the real commands and layout.
   - `.gitignore` appropriate to the language.
   - README: name, one-paragraph purpose, install/run commands. Short.

4. **First commit** with message `Initial scaffold`.

## Rules

- Smallest thing that works. A new project gets one source file with a real
  entry point, a test file with one real test (or none if there's nothing to
  test yet), and config. It does not get plugin systems, config frameworks,
  or directory trees for code that doesn't exist.
- Boring choices within each language (see templates). Don't introduce a new
  build tool, test framework, or layout fashion without being asked.
- If the user's description suggests the wrong type (e.g. "CLI" but it's
  really a library), say so before scaffolding.
