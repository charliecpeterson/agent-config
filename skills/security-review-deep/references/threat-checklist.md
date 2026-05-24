# Threat-Model Checklist

Walk this for every changed file in the diff. For each item, mark ✅ / ⚠️ / N/A with a one-line reason. Don't skip categories silently — saying "N/A: no crypto in this change" is a real review artifact.

---

## 1. Trust boundaries

A trust boundary is anywhere data flows from a less-trusted source to a more-trusted one.

- [ ] External → application (HTTP request, websocket message, file upload, IPC, env var, CLI arg)
- [ ] Untrusted user → privileged operation (admin endpoint, billing op, account modification)
- [ ] Tenant A → tenant B (multi-tenant data isolation)
- [ ] Network → in-process (deserialization, RPC, parsing)
- [ ] Third-party API → your code (you don't control the response shape)

For each boundary: what data crosses, what validation is applied at the boundary, what assumptions does code beyond the boundary make?

## 2. Input validation

- [ ] Every external input has a typed schema (Pydantic, Zod, struct tags, etc.)
- [ ] Length limits on strings, arrays, and uploads
- [ ] Content validation (allowlist > denylist) on enums, IDs, file types, MIME types
- [ ] Numeric bounds (no negative quantities, no `Int.MAX`)
- [ ] Unicode normalization where identity comparison matters (homograph attacks)
- [ ] No "stringly typed" parameters that get later parsed unsafely

## 3. Injection sinks

Search the diff for these sinks and confirm each one is fed only safe inputs:

- [ ] **SQL** — parameterized queries only, no string concatenation, no `f"... {var}"` in raw SQL, no ORM raw modes without binding
- [ ] **Command / shell** — `subprocess` with list args + `shell=False`, no `os.system`, no `eval`, no `shell=True` with user input
- [ ] **OS path** — no path constructed from user input passed to `open`/`os.remove`/etc. without realpath + allowlist check
- [ ] **Template** — Jinja autoescape on, no `| safe` on user input, no SSTI via user-controlled template strings
- [ ] **HTML** — output encoded for context (HTML body vs attribute vs JS vs CSS vs URL)
- [ ] **HTTP headers** — no `\r\n` injection from user input into Set-Cookie / Location
- [ ] **Log** — no `\n` injection allowing fake log lines
- [ ] **NoSQL** — no object-shaped query payloads accepted from JSON (`{"$gt": ""}` bypasses)
- [ ] **LDAP / XPath / XML** — appropriate escaping for the target language
- [ ] **Regex** — no user-supplied patterns (ReDoS); patterns reviewed for catastrophic backtracking

## 4. AuthN / AuthZ

- [ ] Every new endpoint / handler / RPC method has an explicit auth check
- [ ] Auth check happens **before** any side effect or expensive operation
- [ ] Object-level permissions enforced (the resource belongs to the requesting user) — this is IDOR territory
- [ ] No "security through obscurity" — UUIDs are not authorization
- [ ] Role/permission checks use a centralized helper, not ad-hoc string compares
- [ ] Session handling: rotation on privilege change, invalidation on logout, secure cookie flags
- [ ] No JWT `alg: none`; signing key not user-controllable; expiry enforced
- [ ] No timing-unsafe credential comparison (`==` on tokens / hashes)
- [ ] MFA / step-up auth required for sensitive actions where applicable

## 5. Secrets and credentials

- [ ] No hardcoded API keys, tokens, passwords, private keys, connection strings
- [ ] Secrets not logged (including in error messages, request dumps, telemetry)
- [ ] Secrets not embedded in URLs (visible in proxy logs, browser history, Referer)
- [ ] `.env` / `secrets.yaml` not committed
- [ ] Test fixtures don't contain real credentials
- [ ] Secret rotation supported (no assumption of immutable secret)

## 6. Cryptography

- [ ] Algorithms: AES-GCM or ChaCha20-Poly1305 (not ECB, not raw CBC without MAC)
- [ ] Hashes: SHA-256+ for integrity; bcrypt / argon2 / scrypt for passwords (never MD5/SHA-1/plain-SHA-256 for passwords)
- [ ] HMAC for integrity, not raw hash
- [ ] Key length: RSA ≥2048, ECC P-256+, AES ≥128
- [ ] IV / nonce: random per encryption, never reused with the same key
- [ ] No custom crypto. None. Always a red flag.
- [ ] Constant-time comparison for MACs and tokens
- [ ] TLS verification not disabled (`verify=False`, `rejectUnauthorized: false`, `InsecureSkipVerify: true`)
- [ ] Random: cryptographic RNG (`secrets`, `crypto.randomBytes`) for security purposes, never `random` / `Math.random` / `rand()`

## 7. Deserialization

- [ ] No `pickle.load` / `cPickle.load` on untrusted data — EVER
- [ ] No `yaml.load` without `Loader=SafeLoader` (or use `yaml.safe_load`)
- [ ] No Java `ObjectInputStream` / PHP `unserialize` / .NET `BinaryFormatter` on untrusted data
- [ ] JSON parsers configured to reject duplicate keys if order matters
- [ ] XML parsers configured against XXE (`resolve_entities=False`, `defusedxml` for Python)
- [ ] No `eval`, `exec`, `Function()`, dynamic `require` on user input

## 8. SSRF / file inclusion

- [ ] URL fetches: hostname allowlist, no `localhost` / `127.0.0.1` / `169.254.169.254` / `::1` / private RFC 1918 ranges
- [ ] Redirects followed only within the allowlist
- [ ] DNS rebinding considered (resolve once, connect to resolved IP)
- [ ] File paths: realpath + prefix check against a base directory
- [ ] No user-controlled scheme (`file://`, `gopher://`, `dict://`)

## 9. Race conditions / TOCTOU / replay

- [ ] No check-then-act on file existence/permissions (use atomic operations)
- [ ] Database operations use transactions + appropriate isolation, or row-level locking
- [ ] No "check balance, then debit" without lock — use atomic decrement / compare-and-set
- [ ] Idempotency keys for retryable mutations
- [ ] **Replay protection for signed-message endpoints**: signed messages with
  timestamps (Stripe webhooks, JWTs, signed cookies, OAuth requests) must
  reject stale messages — the timestamp/nonce must be *checked*, not just
  parsed. A captured-valid signed message replayed indefinitely is a signature
  failure even though the signature is technically valid.
- [ ] No assumption that an auth check still holds N milliseconds later

## 10. Error handling

- [ ] Stack traces not returned to users in production
- [ ] Exceptions not silently swallowed (`except: pass`, empty catch blocks)
- [ ] No fail-open: if auth check throws, request fails closed
- [ ] Sensitive info (paths, query fragments, internal hosts) not in error messages
- [ ] Errors logged at appropriate level (not as warnings if they break the request)

## 11. Logging and PII

- [ ] No passwords, tokens, session IDs, API keys, full card numbers, SSNs in logs
- [ ] PII logged only with a defined retention + minimization policy
- [ ] Log injection prevented (newline stripping or structured logging)
- [ ] Logs not world-readable / not in the web root
- [ ] Audit log for security-sensitive events (login, permission change, data export)

## 12. Dependencies

(Most of this is covered by OSV-Scanner / the MCP server. Manual checks:)

- [ ] No typosquats — package name matches what the user actually wanted
- [ ] No abandoned packages (last release >2y, no maintainer response)
- [ ] No packages where the maintainer changed recently and suspiciously
- [ ] Pinned versions or lockfile committed
- [ ] License compatible with the project
- [ ] No transitive dep brings in a known-vulnerable version (`osv-scanner` covers this)

## 13. Supply chain

- [ ] No `postinstall` / `preinstall` scripts in new npm deps without scrutiny
- [ ] No dynamic code download at install/build time (`curl | sh`, fetching tarballs from arbitrary URLs)
- [ ] Build scripts don't read secrets and write to network
- [ ] No `eval(fetch(...))` patterns
- [ ] Container base images pinned by digest, not just tag
- [ ] CI uses pinned action versions (not `@main`)

## 14. Concurrency

- [ ] Shared mutable state protected by lock / channel / actor
- [ ] No "check if cache has it, then set" without atomic operations
- [ ] Goroutines / async tasks don't leak (timeout / cancellation propagation)
- [ ] Database connections / file handles closed in finally / `with` / `defer`

## 15. Resource exhaustion (DoS)

- [ ] Request body size limits enforced
- [ ] Upload size and count limits enforced
- [ ] Regex patterns reviewed for catastrophic backtracking (ReDoS) — especially on user input
- [ ] Unbounded loops / recursion guarded by depth/iteration limits
- [ ] Pagination on list endpoints (no "return all rows")
- [ ] Rate limiting on expensive operations
- [ ] Memory caps on parsers (JSON depth, XML entity expansion, decompression bombs)

---

## Bonus: project-specific patterns

Add patterns specific to your codebase here. Examples:

- "All money calculations use `Decimal`, never `float`."
- "Webhook handlers verify the HMAC signature before parsing the body."
- "Background jobs validate the user_id parameter against the calling session."
