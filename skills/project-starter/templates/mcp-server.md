# MCP server project

My standard shape for MCP servers (matches edamcp/chemtoolsmcp). Python +
FastMCP by default; TypeScript only when the server must run where Python
can't (see h2mcp for that shape: `npm install && npm run build`, entry
`dist/index.js`).

## Init

```bash
uv init --name <name> --package
uv add "mcp[cli]"
uv add --dev pytest ruff
```

## Layout

```
<name>/
├── pyproject.toml      console script: <name> = "<pkg>.server:main"
├── README.md           includes the claude mcp add one-liner (below)
├── CLAUDE.md
├── src/<pkg>/
│   ├── __init__.py
│   └── server.py       FastMCP instance + tools; split by domain at ~700 lines
└── tests/              tools are plain functions — test them directly
```

## Conventions

- Tools are thin wrappers over plain, testable functions. The MCP layer
  holds no logic.
- Tool docstrings are written for the calling model: what it does, when to
  use it, what the args mean. They are the API.
- Keep the tool surface small; a 50-tool server loads worse than two
  focused ones. If tools split into modes, support a `--mode` flag like
  edamcp does.
- Deployment: cloned to `~/mcps/<name>` by claude-config's `install.sh`
  (add a line to `PERSONAL_MCPS`). Never registered at user scope —
  inactive by default, enabled per project:

```bash
claude mcp add --scope local <name> -- uv run --directory ~/mcps/<name> <name>
```

- README documents that one-liner plus each tool in a sentence.
