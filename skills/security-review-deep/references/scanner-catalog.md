# Scanner catalog

Loaded by `../SKILL.md` at Step 2 once the diff's languages and surfaces are
known. Everything about *which scanners exist*: per-language commands, the
CI / IaC blocks, the scheduled CodeQL setup, install commands, and the
tested-version table. Run a block only when its target language or surface
appears in the diff (or, for whole-repo audits, the repo). Wrap every
invocation in the `TO` timeout helper defined in SKILL.md.

## Language-specific (gate by file extension in the diff)

```bash
# Python (*.py) — common security antipatterns the model often misses
bandit -r <python-paths> -f json -o "$WORKDIR/bandit.json"

# Go (*.go) — gosec for code patterns, govulncheck for reachable dep vulns
gosec -fmt=json -out="$WORKDIR/gosec.json" ./...
govulncheck -json ./... > "$WORKDIR/govulncheck.json"

# JavaScript / TypeScript (*.js, *.ts, *.jsx, *.tsx)
njsscan --json -o "$WORKDIR/njsscan.json" .

# Ruby / Rails (Gemfile + config/application.rb present)
brakeman -f json -o "$WORKDIR/brakeman.json" --no-progress

# Shell (*.sh, *.bash) — quoting and command-injection catches
shellcheck -f json <shell-files> > "$WORKDIR/shellcheck.json"

# Java / Kotlin (*.java, *.kt, pom.xml, build.gradle)
spotbugs -textui -xml:withMessages -output "$WORKDIR/spotbugs.xml" \
         -pluginList find-sec-bugs.jar <build-output-dirs>

# Rust (Cargo.toml present) — CVE deps, unsafe blocks, panic-prone code
cargo audit --json > "$WORKDIR/cargo-audit.json"
cargo geiger --output-format Json > "$WORKDIR/cargo-geiger.json"
cargo clippy --all-targets --message-format=json -- \
    -W clippy::unwrap_used -W clippy::expect_used \
    -W clippy::panic -W clippy::indexing_slicing \
    > "$WORKDIR/clippy.json"

# C / C++ (*.c, *.cc, *.cpp, *.h, *.hpp) — classic memory-safety class
flawfinder --csv <c-paths> > "$WORKDIR/flawfinder.csv"
cppcheck --enable=warning,performance,portability \
         --output-file="$WORKDIR/cppcheck.txt" --xml <c-paths>
clang-tidy <c-paths> \
    -checks='clang-analyzer-security.*,clang-analyzer-core.*,bugprone-*' \
    > "$WORKDIR/clang-tidy.txt"

# .NET (*.cs, *.csproj, *.sln) — Roslyn-based security analyzer
security-scan <solution.sln> --export="$WORKDIR/security-code-scan.sarif"

# PHP (*.php, composer.json) — taint-mode (psalm) catches injection
# across function boundaries; psalm taint is currently the strongest
# free PHP SAST.
vendor/bin/psalm --taint-analysis --report="$WORKDIR/psalm.sarif"
```

Scanner alternatives worth knowing about:

- **Opengrep** (Jan 2025 community fork of Semgrep CE) is a drop-in
  replacement if Semgrep's licensing changes bite. Same rule format,
  same JSON / SARIF output, same `--config=p/...` packs work. Swap
  the binary name if you need to.

## CI / build / infra surface (gate by file presence)

```bash
# GitHub Actions (.github/workflows/*.yml) — workflow-injection,
# pull_request_target misuse, over-privileged tokens. A repeatedly
# exploited supply-chain class (compromised actions have pivoted into
# PyPI publishes); non-negotiable when workflows are present.
zizmor --format=json .github/workflows/ > "$WORKDIR/zizmor.json"

# Dockerfile (Dockerfile, **/Dockerfile.*) — author-time issues trivy misses
hadolint --format=json $(find . -name 'Dockerfile*' -not -path '*/node_modules/*') > "$WORKDIR/hadolint.json"

# IaC: Terraform (*.tf), Kubernetes (k8s/, helm/), CloudFormation, ARM,
# Bicep, Serverless. Checkov is the broadest open-source IaC scanner
# (tfsec is deprecated, terrascan is archived — verify via
# recent-research before recommending a replacement).
checkov -d . --framework all -o json -s --skip-path node_modules > "$WORKDIR/checkov.json"

# Kubernetes manifest quality (k8s/, helm/, *.yaml with `kind:`). Checkov
# catches policy violations; kube-score catches operational misses
# (resource limits, readiness probes, security contexts) the policy
# scanners miss. Optional layer; run if K8s manifests are present.
kube-score score $(find . -path '*/k8s/*.yaml' -o -path '*/helm/*.yaml') \
            --output-format json > "$WORKDIR/kube-score.json"

# SBOM + cross-check vuln scanning (independent of OSV; surfaces
# advisories OSV occasionally misses, and produces an artifact you can
# diff over time).
syft . -o cyclonedx-json > "$WORKDIR/sbom.cdx.json"
grype sbom:"$WORKDIR/sbom.cdx.json" -o json > "$WORKDIR/grype.json"
```

## Heavier passes for a schedule (CodeQL)

Some scanners are too slow for per-PR but worth running nightly or
weekly. CodeQL is the canonical example: database-backed semantic
analysis with interprocedural taint tracking that catches injection
across function boundaries semgrep / bandit miss. Build time is
minutes to 30+ minutes for large repos, so it does not belong in
the fast path.

Recommended pattern: run CodeQL in a scheduled GitHub Actions job
(free for public repos via Code Scanning; paid for private). Persist
the SARIF artifact to a known path, and let the next per-PR review
ingest it as a "last full-pass" finding set.

```yaml
# .github/workflows/codeql.yml (excerpt)
on:
  schedule: [{cron: "17 4 * * *"}]   # daily 04:17 UTC
jobs:
  analyze:
    runs-on: ubuntu-latest
    permissions: {contents: read, security-events: write}
    strategy:
      matrix:
        language: [python, javascript, go]
    steps:
      - uses: actions/checkout@v4
      - uses: github/codeql-action/init@v3
        with: {languages: '${{ matrix.language }}', queries: security-extended}
      - uses: github/codeql-action/analyze@v3
        with: {output: codeql-results}
      - uses: actions/upload-artifact@v4
        with:
          name: codeql-${{ matrix.language }}-sarif
          path: codeql-results
```

Don't try to run CodeQL inline in the per-PR skill invocation; the
latency makes the skill unusable. Schedule it, ingest it.

## Installing the scanners

The full stack relies on tools that aren't all installed by default. On macOS:

```bash
brew install semgrep gitleaks trivy hadolint shellcheck
pipx install bandit checkov trufflehog zizmor
go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest
go install github.com/securego/gosec/v2/cmd/gosec@latest
go install golang.org/x/vuln/cmd/govulncheck@latest
cargo install cargo-audit
gem install brakeman
# njsscan
pipx install njsscan
# syft + grype
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh  | sh -s -- -b /usr/local/bin
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin
```

## Tested versions

The scanner versions the skill was last exercised against. Drift past these is expected and almost always fine; `install.sh --check` is the live source of truth for what's actually on the system. If a finding looks wrong, the first thing to check is whether the tool version has shifted enough that its rule IDs or output schema changed.

| Tool         | Last-tested version |
| ------------ | ------------------- |
| semgrep      | 1.164.0             |
| bandit       | 1.9.4               |
| gitleaks     | 8.30.1              |
| trufflehog   | (not installed locally; latest stable) |
| trivy        | 0.70.0              |
| osv-scanner  | 2.3.8               |
| pip-audit    | 2.10.0              |
| zizmor       | latest stable       |
| hadolint     | latest stable       |
| checkov      | latest stable       |
| syft / grype | latest stable       |
| njsscan      | latest stable       |
| MCP server   | this repo, current commit |

Update this table when a known-good upgrade lands, not on every release.
