# security-advisories MCP server

Live vulnerability and exploit-intelligence lookups for any MCP client
(Claude Code, Claude Desktop). Pairs with the `security-review-deep`
skill but works standalone.

## Why this exists

LLMs hallucinate CVE IDs and confuse advisory metadata. This server
fronts six authoritative sources behind a small set of well-typed tools
so the model can cite real data instead of inventing it:

| Source       | Best for                                              |
| ------------ | ----------------------------------------------------- |
| OSV.dev      | "is this package@version vulnerable?"                 |
| GitHub GHSA  | rich advisory metadata, CVSS, patched ranges          |
| NVD          | CVE-by-id (note: only ~15-20% enrichment after Apr 2026) |
| CISA KEV     | "is this CVE being weaponized right now?"             |
| FIRST EPSS   | exploit-probability score (0.0-1.0, next 30 days)     |
| Composite    | CVSS + EPSS + KEV → single 0-100 triage score         |

## Tools exposed

| Tool                       | What it does                                                                 |
| -------------------------- | ---------------------------------------------------------------------------- |
| `check_package`            | OSV query for one package@version                                            |
| `check_dependencies_bulk`  | OSV batch query for a whole lockfile (up to 1000 entries, parallel hydrate)  |
| `latest_safe_version`      | Given a vulnerable package@version, return minimum upgrade target(s)         |
| `lookup_cve`               | NVD record for a CVE id                                                      |
| `recent_critical_cves`     | NVD HIGH/CRITICAL CVEs in the last N days, optional keyword filter           |
| `ghsa_get`                 | Full GitHub Security Advisory by GHSA id                                     |
| `ghsa_search`              | GitHub advisory search (best-effort; prefer ghsa_get / check_package)        |
| `kev_lookup`               | CISA Known Exploited Vulnerabilities check                                   |
| `epss_score`               | FIRST.org EPSS exploit-prediction score                                      |
| `composite_risk`           | Combined CVSS + EPSS + KEV triage signal with a 0-100 composite score        |
| `package_health`           | Maintenance signals (last release, total releases, maintainers, abandoned). PyPI + npm.|

## Install

```bash
cd mcp-server
uv sync       # or: pip install -e .
```

Register with Claude Code:

```bash
claude mcp add security-advisories -- \
    uv --directory "$(pwd)" run mcp_security_server.py
```

Or, in Claude Desktop, add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "security-advisories": {
      "command": "uv",
      "args": ["--directory", "/abs/path/to/mcp-server", "run", "mcp_security_server.py"]
    }
  }
}
```

## Optional environment

| Variable        | Effect                                                  |
| --------------- | ------------------------------------------------------- |
| `GITHUB_TOKEN`  | Lifts GHSA rate limit from 60/hr to 5000/hr             |
| `NVD_API_KEY`   | Lifts NVD rate limit (request at nvd.nist.gov)          |

Neither is required for normal use. The KEV catalog and EPSS API have
no auth.

## Operational notes

- **KEV catalog is cached** for 1 hour per process. Cache is rebuilt
  lazily on the next call after expiry.
- **Bulk OSV hydration** runs up to 16 in-flight requests at a time
  (`OSV_HYDRATE_CONCURRENCY`).
- **Response size cap** is 10 MiB per upstream call. Anything larger
  raises rather than being silently truncated.
- **All inputs are validated** (CVE ids by regex, GHSA ids by regex,
  package names by charset, ecosystems normalized via alias map). Bad
  inputs raise `ValueError` rather than being forwarded.
- **Every response** carries `source` and `fetched_at` keys so the
  model can cite provenance and stale caches are visible.

## Triage convention

`composite_risk` returns a `triage_bucket` that the `security-review-deep`
skill uses to slot findings:

| Bucket    | Composite | Trigger conditions                                       |
| --------- | --------- | -------------------------------------------------------- |
| Critical  | >= 90     | In CISA KEV, OR CVSS 9+ with EPSS >= 0.5                 |
| High      | 70-89     | EPSS >= 0.5, OR CVSS 7-9                                 |
| Medium    | 40-69     | CVSS 4-7                                                 |
| Low       | 1-39      | CVSS < 4                                                 |
| Unknown   | 0         | No scoring data available                                |

KEV membership is the strongest available "actively exploited" signal
and overrides everything else.
