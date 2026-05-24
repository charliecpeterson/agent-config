# Code Security Workflow

A three-layer security workflow that runs after commits, bug fixes, and code reviews. Designed to let smaller LLMs operate at senior-pentester level by combining deterministic scanners with live CVE data and structured threat-model analysis.

```
┌──────────────────────────────────────────────────────────────┐
│  Layer 1: pre-commit / CI                                    │
│  Fast deterministic scanners catch the obvious stuff         │
│  semgrep · osv-scanner · trivy · gitleaks · bandit           │
└────────────────────────────┬─────────────────────────────────┘
                             │ findings (SARIF/JSON)
                             ▼
┌──────────────────────────────────────────────────────────────┐
│  Layer 2: security-advisories MCP server                     │
│  Live CVE / advisory queries during review                   │
│  OSV.dev · NVD · GitHub GHSA                                 │
└────────────────────────────┬─────────────────────────────────┘
                             │ grounded vuln data
                             ▼
┌──────────────────────────────────────────────────────────────┐
│  Layer 3: security-review skill                              │
│  LLM orchestration: runs scanners, queries MCP, walks the    │
│  threat-model checklist, triages by exploitability, outputs  │
│  a structured report with suggested patches                  │
└──────────────────────────────────────────────────────────────┘
```

## Why three layers?

- **Scanners alone** miss context. Semgrep flags a SQL concat but can't tell you the input is hardcoded admin config.
- **LLM alone** hallucinates. It will confidently invent CVE-2024-99999 if you don't ground it.
- **MCP alone** is data without judgment.

Together: scanners do recall, MCP keeps the LLM honest about CVEs, the skill provides the structured reasoning that turns raw findings into an actionable review.

## What's in this folder

```
security-workflow/
├── pre-commit/
│   ├── .pre-commit-config.yaml   # Runs locally on `git commit`
│   └── security.yml              # GitHub Actions equivalent for CI
├── mcp-server/
│   ├── mcp_security_server.py    # The MCP server (Python, FastMCP)
│   ├── pyproject.toml
│   └── README.md                 # Install + wire-up instructions
└── skill/
    ├── SKILL.md                  # Claude Code skill entry point
    └── references/
        ├── threat-checklist.md   # 15-category review checklist
        └── report-template.md    # Output format
```

## Setup order

1. **Install the scanners** (one-time, system-wide):
   ```bash
   # macOS
   brew install semgrep trivy gitleaks
   pip install pre-commit bandit osv-scanner

   # Or use the Docker images for each in CI
   ```

2. **Drop the pre-commit config into your repo:**
   ```bash
   cp pre-commit/.pre-commit-config.yaml /path/to/repo/
   cd /path/to/repo && pre-commit install
   ```

3. **Drop the CI workflow:**
   ```bash
   cp pre-commit/security.yml /path/to/repo/.github/workflows/
   ```

4. **Install the MCP server:**
   ```bash
   cd mcp-server && pip install -e .
   claude mcp add security-advisories -- python "$(pwd)/mcp_security_server.py"
   ```
   (Or wire into Claude Desktop via `claude_desktop_config.json` — see `mcp-server/README.md`.)

5. **Install the skill** — depends on your client. For Claude Code, place the `skill/` directory in your skills folder. For Claude Desktop, package and install as a `.skill` file.

## Daily usage

After a commit:
> "security review on the last commit"

After upgrading a dep:
> "I just bumped requests to 2.32.0, any CVEs I should know about?"

Reviewing a PR:
> "audit this PR for vulnerabilities — diff is against main"

The skill will route the request: scope the change → run the scanners → query the MCP for live CVE data → walk the threat checklist → produce a triaged report.

## How it makes small models better

A 7B-class model asked "is this code secure?" will mostly guess. The same model with this workflow has:

- **Real findings** to reason about (from the scanners) instead of inventing them
- **Verified CVE data** (from MCP) instead of hallucinated advisory IDs
- **A checklist** (from the skill) so coverage doesn't depend on what the model happens to remember
- **A report format** so output is consistent and actionable

The model's job shrinks from "find vulnerabilities" (hard, error-prone) to "explain and prioritize the findings these tools surfaced and check whether anything obvious in the diff was missed" (much more tractable).
