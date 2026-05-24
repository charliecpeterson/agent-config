"""
Security Advisories MCP Server
==============================

Exposes live vulnerability lookups to any MCP client (Claude Code, Claude
Desktop, etc.). Queries three complementary sources:

  - OSV.dev     - Google's aggregator (GHSA, PyPI advisories, RustSec,
                  npm advisories, Go vuln DB, OSS-Fuzz, etc.). Best for
                  "is this package@version vulnerable?"
  - GitHub GHSA - Authoritative advisory data with CVSS, fix versions,
                  and patched ranges. Good for richer metadata.
  - NVD         - The canonical CVE database. Best for "tell me about
                  CVE-2024-XXXXX" by ID, and for non-package CVEs
                  (OS, hardware, protocol vulns).

Run with:   uv run mcp_security_server.py
            (or: python mcp_security_server.py)

Add to Claude Code:
    claude mcp add security-advisories -- python /path/to/mcp_security_server.py

Optional env vars:
    GITHUB_TOKEN   - bumps GHSA rate limit from 60/hr to 5000/hr
    NVD_API_KEY    - bumps NVD rate limit (request at nvd.nist.gov)
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("security-advisories")

OSV_API = "https://api.osv.dev/v1"
GHSA_GRAPHQL = "https://api.github.com/graphql"
NVD_API = "https://services.nvd.nist.gov/rest/json/cves/2.0"

# ---------- OSV ----------------------------------------------------------

# OSV's ecosystem identifiers don't always match what users type. Map common
# package-manager names to OSV ecosystem strings.
ECOSYSTEM_ALIASES = {
    "pip": "PyPI", "pypi": "PyPI", "python": "PyPI",
    "npm": "npm", "node": "npm", "nodejs": "npm",
    "cargo": "crates.io", "rust": "crates.io",
    "go": "Go", "golang": "Go",
    "maven": "Maven", "java": "Maven",
    "nuget": "NuGet", "dotnet": "NuGet",
    "gem": "RubyGems", "ruby": "RubyGems",
    "composer": "Packagist", "php": "Packagist",
}


@mcp.tool()
async def check_package(
    ecosystem: str,
    name: str,
    version: str | None = None,
) -> dict[str, Any]:
    """Check whether a specific package (and optionally version) has known
    vulnerabilities via OSV.dev.

    Args:
        ecosystem: Package manager. One of: pip, npm, cargo, go, maven,
                   nuget, gem, composer (aliases accepted).
        name:      Package name (e.g. "requests", "lodash", "log4j-core").
        version:   Optional exact version. If omitted, returns all known
                   advisories for the package across all versions.

    Returns:
        dict with keys: package, version, vulnerability_count, vulnerabilities
        Each vulnerability includes id, summary, severity, affected ranges,
        fixed versions, and references.
    """
    eco = ECOSYSTEM_ALIASES.get(ecosystem.lower(), ecosystem)

    query: dict[str, Any] = {"package": {"name": name, "ecosystem": eco}}
    if version:
        query["version"] = version

    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.post(f"{OSV_API}/query", json=query)
        r.raise_for_status()
        data = r.json()

    vulns = data.get("vulns", [])
    return {
        "package": name,
        "ecosystem": eco,
        "version": version,
        "vulnerability_count": len(vulns),
        "vulnerabilities": [_summarize_osv(v) for v in vulns],
    }


@mcp.tool()
async def check_dependencies_bulk(
    dependencies: list[dict[str, str]],
) -> dict[str, Any]:
    """Check a list of dependencies in one round trip. Much more efficient
    than calling check_package N times when reviewing a full lockfile.

    Args:
        dependencies: List of {"ecosystem": ..., "name": ..., "version": ...}
                      dicts. version is optional per entry.

    Returns:
        dict mapping "ecosystem/name@version" -> list of vulnerability summaries
        Only includes entries that have at least one vulnerability.
    """
    queries = []
    keys = []
    for dep in dependencies:
        eco = ECOSYSTEM_ALIASES.get(dep["ecosystem"].lower(), dep["ecosystem"])
        q: dict[str, Any] = {"package": {"name": dep["name"], "ecosystem": eco}}
        if dep.get("version"):
            q["version"] = dep["version"]
        queries.append(q)
        keys.append(f"{eco}/{dep['name']}@{dep.get('version', '*')}")

    async with httpx.AsyncClient(timeout=30) as client:
        r = await client.post(f"{OSV_API}/querybatch", json={"queries": queries})
        r.raise_for_status()
        data = r.json()

    results: dict[str, list[dict]] = {}
    for key, result in zip(keys, data.get("results", [])):
        vulns = result.get("vulns", [])
        if vulns:
            # Batch results are stubs (id only). Hydrate each one.
            results[key] = []
            for stub in vulns:
                full = await _fetch_osv_by_id(stub["id"])
                if full:
                    results[key].append(_summarize_osv(full))

    return {
        "checked": len(dependencies),
        "vulnerable_count": len(results),
        "vulnerable": results,
    }


@mcp.tool()
async def lookup_cve(cve_id: str) -> dict[str, Any]:
    """Fetch full details for a specific CVE by ID from the NVD.

    Args:
        cve_id: e.g. "CVE-2024-3094", "CVE-2021-44228"

    Returns:
        dict with description, CVSS v3 score + vector, CWE, references,
        affected configurations, and published/modified dates.
    """
    headers = {}
    if api_key := os.environ.get("NVD_API_KEY"):
        headers["apiKey"] = api_key

    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.get(NVD_API, params={"cveId": cve_id}, headers=headers)
        r.raise_for_status()
        data = r.json()

    items = data.get("vulnerabilities", [])
    if not items:
        return {"error": f"No CVE found for {cve_id}"}

    return _summarize_nvd(items[0]["cve"])


@mcp.tool()
async def recent_critical_cves(
    days: int = 7,
    keyword: str | None = None,
) -> dict[str, Any]:
    """List recently published HIGH/CRITICAL CVEs from the NVD. Useful for
    asking "what new zero-days dropped this week?" or filtering by a
    technology you depend on.

    Args:
        days:    Look back this many days (max 120 - NVD API limit).
        keyword: Optional case-insensitive substring to match against
                 CVE descriptions (e.g. "openssl", "nginx", "kubernetes").

    Returns:
        dict with count and list of CVE summaries, sorted newest first.
    """
    days = min(days, 120)
    now = datetime.now(timezone.utc)
    start = now - timedelta(days=days)

    params = {
        "pubStartDate": start.strftime("%Y-%m-%dT%H:%M:%S.000"),
        "pubEndDate": now.strftime("%Y-%m-%dT%H:%M:%S.000"),
        "cvssV3Severity": "HIGH",  # filtered further below to HIGH+CRITICAL
        "resultsPerPage": 200,
    }
    if keyword:
        params["keywordSearch"] = keyword

    headers = {}
    if api_key := os.environ.get("NVD_API_KEY"):
        headers["apiKey"] = api_key

    async with httpx.AsyncClient(timeout=30) as client:
        # NVD only accepts one severity at a time; do two calls and merge.
        results = []
        for sev in ("HIGH", "CRITICAL"):
            params["cvssV3Severity"] = sev
            r = await client.get(NVD_API, params=params, headers=headers)
            r.raise_for_status()
            data = r.json()
            for item in data.get("vulnerabilities", []):
                results.append(_summarize_nvd(item["cve"]))

    results.sort(key=lambda x: x.get("published", ""), reverse=True)
    return {
        "days_searched": days,
        "keyword": keyword,
        "count": len(results),
        "cves": results,
    }


@mcp.tool()
async def ghsa_search(query: str, limit: int = 10) -> dict[str, Any]:
    """Search GitHub Security Advisories (GHSA). Richer metadata than NVD
    for software packages, including patched version ranges and CWE.

    Args:
        query: Free-text search (e.g. "log4j RCE", "express ssrf").
        limit: Max advisories to return (default 10, max 50).

    Returns:
        dict with count and list of advisory summaries.
    """
    token = os.environ.get("GITHUB_TOKEN")
    headers = {"Accept": "application/vnd.github+json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    # REST is simpler than GraphQL for this and doesn't strictly require auth.
    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.get(
            "https://api.github.com/advisories",
            params={"per_page": min(limit, 50), "type": "reviewed"},
            headers=headers,
        )
        r.raise_for_status()
        advisories = r.json()

    # API doesn't support full-text query directly; filter client-side.
    q = query.lower()
    matched = [
        a for a in advisories
        if q in (a.get("summary") or "").lower()
        or q in (a.get("description") or "").lower()
    ][:limit]

    return {
        "query": query,
        "count": len(matched),
        "advisories": [_summarize_ghsa(a) for a in matched],
    }


# ---------- helpers ------------------------------------------------------

async def _fetch_osv_by_id(vuln_id: str) -> dict | None:
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.get(f"{OSV_API}/vulns/{vuln_id}")
        if r.status_code != 200:
            return None
        return r.json()


def _summarize_osv(v: dict) -> dict[str, Any]:
    severity = None
    for s in v.get("severity", []) or []:
        if s.get("type") == "CVSS_V3":
            severity = s.get("score")
            break

    fixed_versions = []
    for affected in v.get("affected", []) or []:
        for r in affected.get("ranges", []) or []:
            for event in r.get("events", []) or []:
                if "fixed" in event:
                    fixed_versions.append(event["fixed"])

    aliases = v.get("aliases", []) or []
    cve_ids = [a for a in aliases if a.startswith("CVE-")]

    return {
        "id": v.get("id"),
        "cve_ids": cve_ids,
        "summary": v.get("summary"),
        "details": (v.get("details") or "")[:500],
        "severity_cvss": severity,
        "fixed_versions": list(set(fixed_versions)),
        "published": v.get("published"),
        "references": [r.get("url") for r in (v.get("references") or [])[:5]],
    }


def _summarize_nvd(cve: dict) -> dict[str, Any]:
    descs = cve.get("descriptions", [])
    desc = next((d["value"] for d in descs if d.get("lang") == "en"), "")

    metrics = cve.get("metrics", {})
    cvss = None
    severity = None
    vector = None
    for key in ("cvssMetricV31", "cvssMetricV30"):
        if entries := metrics.get(key):
            data = entries[0].get("cvssData", {})
            cvss = data.get("baseScore")
            severity = data.get("baseSeverity")
            vector = data.get("vectorString")
            break

    cwes = []
    for weakness in cve.get("weaknesses", []) or []:
        for d in weakness.get("description", []) or []:
            if d.get("value", "").startswith("CWE-"):
                cwes.append(d["value"])

    return {
        "id": cve.get("id"),
        "description": desc[:600],
        "cvss_score": cvss,
        "severity": severity,
        "cvss_vector": vector,
        "cwes": list(set(cwes)),
        "published": cve.get("published"),
        "last_modified": cve.get("lastModified"),
        "references": [r.get("url") for r in (cve.get("references") or [])[:5]],
    }


def _summarize_ghsa(a: dict) -> dict[str, Any]:
    return {
        "ghsa_id": a.get("ghsa_id"),
        "cve_id": a.get("cve_id"),
        "summary": a.get("summary"),
        "severity": a.get("severity"),
        "cvss_score": (a.get("cvss") or {}).get("score"),
        "published": a.get("published_at"),
        "vulnerabilities": [
            {
                "package": (v.get("package") or {}).get("name"),
                "ecosystem": (v.get("package") or {}).get("ecosystem"),
                "vulnerable_version_range": v.get("vulnerable_version_range"),
                "patched_versions": v.get("patched_versions"),
            }
            for v in (a.get("vulnerabilities") or [])
        ],
        "html_url": a.get("html_url"),
    }


if __name__ == "__main__":
    mcp.run()
