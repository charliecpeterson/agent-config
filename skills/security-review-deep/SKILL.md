---
name: security-review-deep
description: Use this skill for in-depth, scanner-grounded security audits — distinct from Claude Code's built-in lightweight `/security-review`. Trigger on "deep security review", "full security audit", "review this for vulnerabilities with scanners", "check for CVEs", "audit this PR", "scan my dependencies", "did anything new drop affecting us", or any time the user wants senior-pentester-level scrutiny that combines SAST, dependency CVE lookup, and a structured threat-model checklist. Also use proactively after the user finishes a bug fix, refactor, or feature touching authentication, authorization, input handling, file I/O, network calls, cryptography, deserialization, or dependency upgrades. Runs the right scanners (semgrep, osv-scanner, trivy, gitleaks, bandit), queries live CVE data via MCP, applies a 15-category threat-model checklist, and produces a triaged report — letting smaller models punch above their weight by grounding analysis in tool output rather than memory.
---

# Security Review

A disciplined, repeatable process for catching vulnerabilities in a code change. Designed to make any model — large or small — review like a senior security engineer by combining deterministic scanners, live advisory data, and a structured threat-model walkthrough.

## When to use this skill

- After a commit, in a pre-push hook, or in CI
- When reviewing a PR or diff
- When auditing a dependency upgrade
- When the user asks "is this safe?" or anything in the same neighborhood
- Proactively after the user finishes work that touches sensitive surface area (auth, file I/O, deserialization, network, crypto, IPC, parsing user input)

If unsure whether to trigger: trigger. False positives here are cheap; missing a vuln is not.

## The process

Always work in this order. **Do not skip to LLM analysis without running the scanners first** — that's how you end up hallucinating CVE numbers and missing real issues.

### Step 1 — Scope the change

Determine what to review:

```bash
# For a post-commit / pre-push review:
git diff HEAD~1 HEAD --stat
git diff HEAD~1 HEAD

# For a PR review (against main):
git diff origin/main...HEAD --stat
git diff origin/main...HEAD

# For an audit of the whole repo:
# scope is everything; note this and warn the user it will be slower
```

Capture:
- list of changed files
- any dependency manifests touched (`package.json`, `package-lock.json`, `requirements.txt`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `pom.xml`, `Gemfile.lock`, etc.)
- whether the change touches any **sensitive surface** (see checklist below)

### Step 2 — Run the deterministic scanners

Run all available scanners on the scoped change. Don't try to *be* the scanner — use them.

```bash
# SAST — pattern-based vuln detection

WORKDIR="${TMPDIR:-/tmp}/security-review-$$"
mkdir -p "$WORKDIR"

semgrep --config=p/default --config=p/security-audit \
        --config=p/owasp-top-ten --config=p/cwe-top-25 \
        --json --quiet <changed-files-or-dir> > "$WORKDIR/semgrep.json"

# Dependency CVEs (Google's OSV aggregator)
osv-scanner scan source -r --format=json --output="$WORKDIR/osv.json" .

# Filesystem / IaC / container vulns
trivy fs --severity HIGH,CRITICAL --format=json --output="$WORKDIR/trivy.json" .

# Secrets
gitleaks detect --no-banner --report-format=json --report-path="$WORKDIR/gitleaks.json"

# Python-specific (if applicable)
bandit -r <python-paths> -f json -o "$WORKDIR/bandit.json"
```

If any tool is missing, note it and continue with the rest. Do not refuse to proceed.

Read each JSON output and build a unified findings list with: file, line, rule, severity, message, raw tool source.

### Step 3 — Pull live advisory context (MCP first, scanners as fallback)

**If the `security-advisories` MCP server is registered, use it before any
other dependency-scanning approach.** It's faster, doesn't need a venv, and
returns structured data Claude can cite without paraphrasing.

Order of preference for dependency CVE lookups:
1. **MCP** — `check_dependencies_bulk` for whole lockfiles, `check_package` for
   single bumped deps, `lookup_cve` for any CVE ID you encounter.
2. **osv-scanner** if the MCP isn't registered.
3. Hand-rolled OSV.dev API calls (curl, Python urllib) only as a last resort
   if both above fail.

Do NOT fall back to "recall the CVE from memory" — that's how CVE IDs get
hallucinated. If the tools aren't available, say so explicitly in the report.

### Step 4 — Apply the threat-model checklist to the diff

This is where the LLM adds value beyond scanners. For **every changed file**, walk the checklist below and write down what you find. Do not just say "looks good" — name the specific function, line, and reason for each item you clear or flag.

Read `references/threat-checklist.md` for the full list. The top categories:

1. **Trust boundaries** — does this code cross one (user → server, low-priv → high-priv, network → process)? What data flows across?
2. **Input validation** — every external input typed, length-checked, content-validated before use
3. **Injection sinks** — SQL, command, LDAP, XPath, template, log, header, NoSQL, ORM-raw
4. **AuthN / AuthZ** — is every new endpoint/handler protected? Is the check before the side effect? Are object-level permissions enforced (IDOR)?
5. **Secrets / credentials** — hardcoded, logged, sent to telemetry, embedded in URLs, committed to repo?
6. **Crypto** — algorithm choice, key length, IV/nonce reuse, MAC-then-encrypt errors, custom crypto (red flag)
7. **Deserialization** — pickle, yaml.load (not safe_load), Java/PHP unserialize, anything that turns bytes into objects
8. **SSRF / file inclusion** — URL or path constructed from user input and then fetched/opened
9. **Race conditions / TOCTOU** — check-then-use patterns on files, tokens, balances
10. **Error handling** — stack traces leaked, exceptions swallowed silently, fail-open patterns
11. **Logging & PII** — secrets, tokens, full PII in logs; unbounded log growth
12. **Dependencies** — covered by Step 3, but also: typosquats, abandoned packages, suspicious new maintainers
13. **Supply chain** — install/build scripts, postinstall hooks, dynamic code loading
14. **Concurrency** — shared mutable state, locking
15. **Resource exhaustion** — unbounded loops, allocations, recursion, regex (ReDoS)

For each item: ✅ cleared (with brief reason), ⚠️ flagged (with file:line + explanation), or N/A.

### Step 5 — Triage and prioritize

You will likely have more findings than the user wants to act on. Rank by **exploitability × impact**, not by scanner severity alone:

- **Critical** — exploitable now, no auth required, leads to RCE / data exfil / auth bypass
- **High** — exploitable with some condition (auth'd user, specific input), or undermines a security boundary
- **Medium** — defense-in-depth issues, hardening gaps, theoretical-but-real
- **Low** — informational, style, "should fix eventually"
- **Noise** — scanner false positives. Explicitly mark these and explain *why* it's a false positive — don't just drop them.

### Step 6 — Output the report

Use the format in `references/report-template.md`. Key principles:

- **Lead with what's actually exploitable.** Don't bury a CRITICAL under 40 LOW findings.
- **Every finding gets a fix.** Suggested patch, not just "be more careful."
- **Cite the source** for every claim — which scanner, which CVE, which line of code.
- **Distinguish what you ran from what you didn't.** "Semgrep + OSV + Trivy on the diff. Did not run dynamic analysis or fuzzing."
- **No padding.** No "in conclusion, security is important." End when the work ends.

If everything passes, the report can be three lines. If it doesn't, it can be ten pages. Length follows findings, never the other way around.

## Failure modes to actively avoid

- **Hallucinating CVE numbers.** Only cite CVEs returned by `lookup_cve` or present in scanner output. Never reconstruct from memory.
- **"It looks fine."** If you haven't run the scanners or walked the checklist, you don't know that.
- **Over-trusting a single scanner.** Semgrep misses things OSV catches and vice versa. Run multiple.
- **Treating scanner severity as final.** A CRITICAL Semgrep finding on dead code is less important than a MEDIUM one in a live auth path. Re-rank based on context.
- **Burying lede.** Top of the report is the worst finding, always.
- **Dropping findings without explanation.** If you decide a finding is a false positive, say so and say why. Never silently omit.
- **Never cite a CVE ID that didn't come directly from a tool output.**
  Every CVE-XXXX-NNNN in the report must be traceable to a specific tool
  invocation (MCP `lookup_cve`, OSV-Scanner JSON, GHSA advisory result). If
  you find yourself typing a CVE ID from memory or inference, stop — call
  `lookup_cve` to verify it exists and matches your claim, or remove it.

## Lightweight mode

If the user wants something fast (pre-commit hook, sub-30-second turnaround):

1. Run only `semgrep --config=p/security-audit` and `gitleaks` on the diff
2. Skip the MCP live-CVE pass unless a dependency manifest was touched
3. Apply only the top 5 checklist categories (1, 2, 3, 4, 5)
4. Output a compact one-screen report

Tell the user this is the lightweight pass and a fuller review can be run separately.

## When you're stuck

If a scanner errors out, capture the error verbatim, note which scanner, and continue with the others. The review is still valuable even if one tool is broken.

If the diff is enormous (>2000 lines changed), tell the user up front: full review will take time, and offer to either (a) batch by directory, or (b) focus on the most sensitive files first based on filename heuristics (anything matching `auth`, `login`, `password`, `crypto`, `admin`, `payment`, `upload`, `parse`, `exec`, `*.sql`, etc.).
