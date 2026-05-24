# Report Template

Use this structure. Drop sections that don't apply. Lead with the worst finding.

---

## Security Review — `<commit-sha or PR title>`

**Scope:** `<files changed>` (`+N -M` lines across `<n>` files)
**Scanners run:** semgrep ✓, osv-scanner ✓, trivy ✓, gitleaks ✓, bandit ✓ (or note skipped)
**Live CVE data:** via `security-advisories` MCP (or note absent)
**Verdict:** ⛔ Block / ⚠️ Fix before merge / ✅ Looks clean / 🔍 Needs human eyes

---

## Critical findings

> Only items that are exploitable now and have material impact. If none, write "None."

### 1. `<short descriptive title>`
**File:** `path/to/file.py:42`
**Category:** SQL injection / IDOR / RCE via deserialization / etc.
**CWE / CVE:** CWE-89 / CVE-2024-XXXXX (if applicable)
**Source:** semgrep rule `python.django.security.injection.sql.sql-injection`

**What's wrong:**
> 2–4 sentences explaining the actual vulnerability in plain language. Show the relevant code snippet.

**Why it's exploitable:**
> What an attacker would do, what they'd get, what they need to start (no auth? auth'd user? specific role?).

**Suggested fix:**
```python
# Before
query = f"SELECT * FROM users WHERE id = {user_id}"

# After
query = "SELECT * FROM users WHERE id = %s"
cursor.execute(query, (user_id,))
```

---

## High-severity findings

(Same structure, condensed.)

---

## Medium / hardening

(Short bullet list — one line each — with file:line and a one-line suggestion. No need to expand each.)

- `auth/middleware.py:88` — JWT expiry not checked; add `exp` validation
- `api/upload.py:31` — no size limit on upload body; add `MAX_UPLOAD_BYTES`

---

## Dependency vulnerabilities

(Skip section if none. Otherwise, table:)

| Package | Version | Advisory | Severity | Fixed in | Notes |
|---|---|---|---|---|---|
| requests | 2.19.1 | CVE-2018-18074 | High | 2.20.0 | exposes Authorization header on redirect |
| ... | | | | | |

---

## Secrets

(Skip section if none.)

- `config/db.example.yaml:12` — looks like a real Postgres URL with credentials. Rotate and move to env.

---

## False positives / not actionable

> Findings you decided not to flag, with a one-line reason each. This is important — it shows the user you saw them and made a judgment call, not that you missed them.

- semgrep `generic.html-templates.security.unquoted-attribute-var` on `templates/admin.html:14` — value is a numeric ID from the trusted session, not user input

---

## What was NOT reviewed

> Be honest about coverage.

- Dynamic / runtime analysis (no fuzzing performed)
- Browser-side XSS in rendered output (no headless browser run)
- Authn flows end-to-end (would need integration test harness)
- The `vendor/` directory (out of scope)

---

## Suggested next steps

> Maximum 3 bullets. Concrete actions, in priority order.

1. Patch the SQL injection in `users.py:42` before merging.
2. Bump `requests` to `≥2.32.0` to clear CVE-2018-18074 and CVE-2023-32681.
3. Add a Semgrep custom rule for the project's `unsafe_eval` helper.
