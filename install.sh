#!/usr/bin/env bash
# Symlink this repo's Claude Code config files into ~/.claude/ so the same
# CLAUDE.md, userprofile.md, style.md, communication.md, engineering.md,
# skills, and sub-agents are active wherever the repo is cloned. Existing real
# files at a target path
# are backed up to ~/.claude/<name>.backup-YYYYMMDD-HHMMSS first.
#
# Portable skills (no Claude-Code sub-agent / MCP dependency) are ALSO linked
# into ~/.agents/skills/ so Codex, pi, and opencode pick them up; Crush is
# pointed at the same dir via skills_paths in its crush.json. The global rules
# (userprofile/style/communication/engineering) are concatenated into
# ~/.codex/AGENTS.md, since non-Claude agents don't resolve CLAUDE.md @imports.
#
# Config files and skills install non-interactively. The script then prompts,
# once each, to clone any personal MCP repos (PERSONAL_MCPS, into ~/mcps/,
# registered per-project with `claude mcp add --scope local`, see README) and
# to install the security-review-deep tools. With no terminal attached it
# takes each prompt's default and does not block.
#
# Re-runnable. Already-linked files and already-cloned MCPs are left as-is.
#
# Usage:
#   ./install.sh          # config + skills, then prompt for MCPs and security tools
#   ./install.sh --check  # verify install + report missing tools
#   ./install.sh --help   # show this usage

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
STAMP="$(date +%Y%m%d-%H%M%S)"

# Cross-agent skill dir read natively by Codex, pi, and opencode, and by Crush
# via skills_paths. Only skills in PORTABLE_SKILLS land here.
AGENTS_SKILLS_DIR="$HOME/.agents/skills"
CODEX_DIR="$HOME/.codex"
OPENCODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"

# Skills with no Claude-Code-specific machinery (no spawned sub-agents, no
# bundled MCP server) — safe to expose to other agent CLIs. The heavy skills
# (code-review-deep, deep-planner, writing-architect, security-review-deep)
# stay Claude-only: their SKILL.md would load elsewhere but then half-execute.
PORTABLE_SKILLS=(
  bug-hunter
  dyslexia-friendly
  editor
  human-writer
  presentation-designer
  project-starter
  recent-research
  session-handoff
  stampede3-debug
  stampede3-submit
)

CHECK_ONLY=0

# Personal MCP servers to make available on this machine. The script clones
# each to ~/mcps/<name> and runs `uv sync`; it does NOT register them with
# Claude Code, so they all stay inactive by default. Enable one only where you
# need it with `claude mcp add --scope local` (see README) so its tools load
# there and nowhere else.
# Format: "name|git-url".
MCPS_DIR="$HOME/mcps"
PERSONAL_MCPS=(
  "edamcp|https://github.com/charliecpeterson/edamcp.git"
  "chemtoolsmcp|https://github.com/charliecpeterson/chemtoolsmcp.git"
  "comfyui_mcp|https://github.com/charliecpeterson/comfyui_mcp.git"
  "office-google-mac-mcp|https://github.com/charliecpeterson/office-google-mac-mcp.git"
  "h2mcp|https://github.com/charliecpeterson/h2mcp.git"
)

# Build a freshly cloned MCP: uv for Python repos, npm (+ build script if one
# exists) for node repos.
sync_mcp() {
  local path="$1" name
  name="$(basename "$path")"
  if [[ -f "$path/pyproject.toml" ]]; then
    if ! command -v uv >/dev/null 2>&1; then
      echo "  manual   $name: install uv, then run 'uv sync' in $path"
      return 1
    fi
    (cd "$path" && uv sync --quiet)
  elif [[ -f "$path/package.json" ]]; then
    if ! command -v npm >/dev/null 2>&1; then
      echo "  manual   $name: install node, then 'npm install && npm run build' in $path"
      return 1
    fi
    (cd "$path" && npm install --silent \
      && { ! grep -q '"build"' package.json || npm run --silent build; })
  fi
}

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Run with --help for usage." >&2
      exit 2
      ;;
  esac
done

mkdir -p "$CLAUDE_DIR"
mkdir -p "$CLAUDE_DIR/skills"
mkdir -p "$CLAUDE_DIR/agents"
mkdir -p "$AGENTS_SKILLS_DIR"

link_file() {
  local src="$1" dest="$2"
  if [[ -L "$dest" ]]; then
    local current
    current="$(readlink "$dest")"
    if [[ "$current" == "$src" ]]; then
      echo "  ok       $dest -> $src"
      return
    fi
    echo "  relink   $dest (was: $current)"
    rm "$dest"
  elif [[ -e "$dest" ]]; then
    local backup="${dest}.backup-${STAMP}"
    echo "  backup   $dest -> $backup"
    mv "$dest" "$backup"
  else
    echo "  new      $dest"
  fi
  ln -s "$src" "$dest"
}

is_portable_skill() {
  local name="$1" s
  for s in "${PORTABLE_SKILLS[@]}"; do
    [[ "$s" == "$name" ]] && return 0
  done
  return 1
}

# Remove symlinks that point into this repo but whose target no longer exists
# (a skill or agent that was deleted or moved out of the repo).
prune_dangling() {
  local dir="$1" link target
  [[ -d "$dir" ]] || return 0
  for link in "$dir"/*; do
    [[ -L "$link" ]] || continue
    target="$(readlink "$link")"
    if [[ "$target" == "$REPO_DIR"/* && ! -e "$link" ]]; then
      echo "  prune    $link (target gone: $target)"
      rm "$link"
    fi
  done
}

# Point Crush at ~/.agents/skills via skills_paths. Only touch crush.json if
# Crush has already been set up (its config dir exists), so we never plant a
# partial config that disrupts first-run onboarding.
configure_crush_skills_path() {
  local cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/crush"
  local cfg="$cfg_dir/crush.json"
  if [[ ! -d "$cfg_dir" ]]; then
    echo "  skip     crush not set up; add \"$AGENTS_SKILLS_DIR\" to skills_paths if you install it"
    return
  fi
  if [[ ! -f "$cfg" ]]; then
    printf '{\n  "skills_paths": ["%s"]\n}\n' "$AGENTS_SKILLS_DIR" > "$cfg"
    echo "  new      $cfg (skills_paths -> $AGENTS_SKILLS_DIR)"
    return
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "  manual   add \"$AGENTS_SKILLS_DIR\" to skills_paths in $cfg (jq not found)"
    return
  fi
  if jq -e --arg p "$AGENTS_SKILLS_DIR" '(.skills_paths // []) | index($p)' "$cfg" >/dev/null 2>&1; then
    echo "  ok       crush skills_paths already includes $AGENTS_SKILLS_DIR"
    return
  fi
  local tmp; tmp="$(mktemp)"
  if jq --arg p "$AGENTS_SKILLS_DIR" '.skills_paths = ((.skills_paths // []) + [$p] | unique)' "$cfg" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$cfg"
    echo "  update   $cfg (added $AGENTS_SKILLS_DIR to skills_paths)"
  else
    rm -f "$tmp"
    echo "  fail     couldn't edit $cfg; add \"$AGENTS_SKILLS_DIR\" to skills_paths by hand"
  fi
}

# Codex and opencode can't resolve the @imports in CLAUDE.md, so flatten the
# four rule files into a real AGENTS.md at each agent's global-rules path.
# Regenerated each run; a pre-existing hand-written file is backed up once.
# (pi has no documented global-rules file, so it's skills-only.)
write_flattened_rules() {
  local dest="$1" label="$2"
  local marker="<!-- generated by claude-config install.sh — edits are overwritten -->"
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" ]] && ! head -n1 "$dest" | grep -qF "$marker"; then
    local backup="${dest}.backup-${STAMP}"
    echo "  backup   $dest -> $backup"
    mv "$dest" "$backup"
  fi
  {
    echo "$marker"
    echo "<!-- Source: $REPO_DIR — userprofile/style/communication/engineering. Regenerate with ./install.sh -->"
    for f in userprofile.md style.md communication.md engineering.md; do
      [[ -f "$REPO_DIR/$f" ]] || continue
      echo
      cat "$REPO_DIR/$f"
    done
  } > "$dest"
  echo "  write    $dest ($label)"
}

# Yes/no prompt. Returns 0 for yes. Without a terminal (piped, CI) it takes
# the default and does not block, so unattended runs still do config + skills.
ask_yn() {
  local q="$1" default="${2:-N}" reply hint
  if [[ ! -t 0 ]]; then
    [[ "$default" == "Y" ]] && return 0 || return 1
  fi
  hint="[y/N]"; [[ "$default" == "Y" ]] && hint="[Y/n]"
  read -r -p "$q $hint " reply || true
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy] ]]
}

# Python scanners install the same way on macOS and Linux via uv's tool dir.
uv_tool_install() {
  local pkg="$1" cmd="${2:-$1}"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  ok       $cmd already installed"
    return
  fi
  echo "  install  $cmd (uv tool)"
  uv tool install --quiet "$pkg" >/dev/null 2>&1 \
    || echo "  fail     $cmd (try: uv tool install $pkg)"
}

# Go binaries have no clean no-sudo cross-distro installer worth scripting:
# use brew if present, otherwise print an exact manual-install hint.
binary_install() {
  local cmd="$1" brew_name="$2" hint="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  ok       $cmd already installed"
    return
  fi
  if command -v brew >/dev/null 2>&1; then
    echo "  install  $cmd (brew)"
    brew install "$brew_name" >/dev/null 2>&1 || echo "  fail     $cmd (try: brew install $brew_name)"
  else
    echo "  manual   $cmd: $hint"
  fi
}

build_and_register_advisories_mcp() {
  local mcp_dir="$REPO_DIR/skills/security-review-deep/mcp-server"
  [[ -f "$mcp_dir/mcp_security_server.py" ]] || return 0
  echo
  echo "MCP server (security-advisories):"
  if [[ -d "$mcp_dir/.venv" ]]; then
    echo "  ok       venv exists at $mcp_dir/.venv"
  else
    echo "  build    uv venv + install at $mcp_dir"
    (cd "$mcp_dir" && uv venv >/dev/null 2>&1 && uv pip install -e . >/dev/null 2>&1) \
      || echo "  fail     uv venv/install (try manually in $mcp_dir)"
  fi

  if command -v claude >/dev/null 2>&1; then
    if claude mcp list 2>/dev/null | grep -qE "(^|[[:space:]])security-advisories[: ]"; then
      echo "  ok       MCP already registered as 'security-advisories' (user scope)"
    elif [[ -x "$mcp_dir/.venv/bin/python" ]]; then
      echo "  register MCP server with Claude Code (user scope)"
      local mcp_err
      if mcp_err=$(claude mcp add --scope user security-advisories \
          -- "$mcp_dir/.venv/bin/python" "$mcp_dir/mcp_security_server.py" 2>&1); then
        echo "  ok       registered"
      else
        echo "  fail     claude mcp add returned:"
        echo "$mcp_err" | sed 's/^/             /'
        echo "           register manually with:"
        echo "             claude mcp add --scope user security-advisories -- \\"
        echo "               $mcp_dir/.venv/bin/python $mcp_dir/mcp_security_server.py"
      fi
    else
      echo "  skip     MCP venv not built yet; can't register"
    fi
  else
    echo "  skip     claude CLI not on \$PATH; register MCP manually later:"
    echo "           claude mcp add --scope user security-advisories -- \\"
    echo "             $mcp_dir/.venv/bin/python $mcp_dir/mcp_security_server.py"
  fi
}

install_security_tools() {
  echo "Security tools:"
  if ! command -v uv >/dev/null 2>&1; then
    echo "  skip     uv not found; install it first: https://docs.astral.sh/uv/getting-started/installation/"
    return 0
  fi

  # Core multi-language SAST + secrets + deps
  uv_tool_install semgrep
  uv_tool_install bandit
  uv_tool_install pip-audit

  binary_install gitleaks gitleaks "download a release from https://github.com/gitleaks/gitleaks/releases"
  binary_install trufflehog trufflehog "brew install trufflesecurity/trufflehog/trufflehog (or release from https://github.com/trufflesecurity/trufflehog/releases)"
  binary_install trivy trivy "curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b ~/.local/bin"
  binary_install osv-scanner osv-scanner "go install github.com/google/osv-scanner/cmd/osv-scanner@latest (or a release from https://github.com/google/osv-scanner/releases)"

  # CI / build / infra hardening
  uv_tool_install zizmor       # GitHub Actions workflow security
  uv_tool_install checkov      # IaC: Terraform / K8s / Helm / CFN / ARM / Bicep
  binary_install hadolint hadolint "download a release from https://github.com/hadolint/hadolint/releases"
  binary_install shellcheck shellcheck "apt/yum/dnf install shellcheck (or release from https://github.com/koalaman/shellcheck/releases)"

  # JS/TS language layer (Python-installable, sees React/Express patterns)
  uv_tool_install njsscan

  # C/C++ memory-safety scanners (Python-installable / brew-installable)
  uv_tool_install flawfinder
  binary_install cppcheck cppcheck "apt/yum/dnf install cppcheck (or release from https://github.com/danmar/cppcheck/releases)"
  binary_install clang-tidy llvm "brew install llvm; ensure /opt/homebrew/opt/llvm/bin is on PATH (ships with LLVM, not standalone)"

  # SBOM + cross-check vuln scanning
  binary_install syft syft "curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b ~/.local/bin"
  binary_install grype grype "curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b ~/.local/bin"

  # Optional Kubernetes manifest scanner (complements checkov)
  binary_install kube-score kube-score "brew install kube-score (or release from https://github.com/zegl/kube-score/releases)"

  # Language-specific tools that need their own toolchain: only flag, don't auto-install
  for pair in \
    "gosec|go install github.com/securego/gosec/v2/cmd/gosec@latest" \
    "govulncheck|go install golang.org/x/vuln/cmd/govulncheck@latest" \
    "staticcheck|go install honnef.co/go/tools/cmd/staticcheck@latest" \
    "brakeman|gem install brakeman" \
    "cargo-audit|cargo install cargo-audit" \
    "cargo-geiger|cargo install cargo-geiger" \
    "clippy-driver|rustup component add clippy" \
    "security-scan|dotnet tool install --global security-scan" \
    "psalm|composer require --dev vimeo/psalm phpstan/phpstan ; vendor/bin/psalm --init"
  do
    cmd="${pair%%|*}"; hint="${pair##*|}"
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "  ok       $cmd already installed"
    else
      echo "  manual   $cmd: $hint"
    fi
  done

  build_and_register_advisories_mcp

  cat <<'EOF'

If uv installed any tools just now, make sure ~/.local/bin is on your PATH.
Optional: set these env vars in your shell profile for higher API rate limits:
  export GITHUB_TOKEN="ghp_..."   # any classic token, no scopes needed
  export NVD_API_KEY="..."        # free at nvd.nist.gov/developers/request-an-api-key
EOF
}

# ---------------------------------------------------------------------------
# Doctor / --check mode
# ---------------------------------------------------------------------------
run_check() {
  local missing=0
  echo "Repo:    $REPO_DIR"
  echo "Target:  $CLAUDE_DIR"
  echo

  echo "Synced files:"
  for name in CLAUDE.md userprofile.md style.md communication.md engineering.md settings.json; do
    local dest="$CLAUDE_DIR/$name"
    if [[ -L "$dest" ]] && [[ "$(readlink "$dest")" == "$REPO_DIR/$name" ]]; then
      echo "  ✓ $name"
    elif [[ -e "$dest" ]]; then
      echo "  ✗ $name (exists but not linked to repo)"
      missing=1
    elif [[ -f "$REPO_DIR/$name" ]]; then
      echo "  ✗ $name (missing from ~/.claude)"
      missing=1
    fi
  done

  echo
  echo "Skills linked:"
  local n=0
  for link in "$CLAUDE_DIR/skills"/*; do
    [[ -L "$link" ]] || continue
    local target
    target="$(readlink "$link")"
    if [[ "$target" == "$REPO_DIR"/* ]]; then
      if [[ -e "$link" ]]; then
        echo "  ✓ $(basename "$link")"
        ((n++)) || true
      else
        echo "  ✗ $(basename "$link") (dangling — target gone; re-run ./install.sh to prune)"
        missing=1
      fi
    fi
  done
  [[ "$n" -eq 0 ]] && { echo "  (none)"; missing=1; }

  if [[ -d "$REPO_DIR/agents" ]]; then
    echo
    echo "Agents linked:"
    local agents_found=0
    for link in "$CLAUDE_DIR/agents"/*.md; do
      [[ -L "$link" ]] || continue
      local target
      target="$(readlink "$link")"
      if [[ "$target" == "$REPO_DIR"/agents/* ]]; then
        echo "  ✓ $(basename "$link")"
        ((agents_found++)) || true
      fi
    done
    [[ "$agents_found" -eq 0 ]] && { echo "  (none — re-run ./install.sh)"; missing=1; }
  fi

  echo
  echo "Cross-agent (Codex / pi / opencode / Crush):"
  local pn=0 ps
  for ps in "$AGENTS_SKILLS_DIR"/*; do
    [[ -L "$ps" ]] || continue
    [[ "$(readlink "$ps")" == "$REPO_DIR"/* ]] && { echo "  ✓ ~/.agents/skills/$(basename "$ps")"; ((pn++)) || true; }
  done
  [[ "$pn" -eq 0 ]] && echo "  ✗ no portable skills in ~/.agents/skills (re-run ./install.sh)"
  for af in "$CODEX_DIR/AGENTS.md:Codex" "$OPENCODE_DIR/AGENTS.md:opencode"; do
    if [[ -f "${af%%:*}" ]]; then
      echo "  ✓ ${af%%:*} (${af##*:})"
    else
      echo "  ✗ ${af%%:*} missing (re-run ./install.sh)"
    fi
  done
  local crush_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/crush/crush.json"
  if [[ -f "$crush_cfg" ]] && command -v jq >/dev/null 2>&1 \
      && jq -e --arg p "$AGENTS_SKILLS_DIR" '(.skills_paths // []) | index($p)' "$crush_cfg" >/dev/null 2>&1; then
    echo "  ✓ crush skills_paths -> ~/.agents/skills"
  else
    echo "  - crush not pointed at ~/.agents/skills (only matters if you use Crush)"
  fi

  if [[ "${#PERSONAL_MCPS[@]}" -gt 0 ]]; then
    echo
    echo "Personal MCP repos (~/mcps; register per-project, see README):"
    for entry in "${PERSONAL_MCPS[@]}"; do
      local mcp_name="${entry%%|*}"
      if [[ -d "$MCPS_DIR/$mcp_name/.git" ]]; then
        echo "  ✓ $mcp_name"
      elif [[ -d "$HOME/projects/$mcp_name/.git" ]]; then
        echo "  ✗ $mcp_name (at ~/projects/$mcp_name, old layout; mv to $MCPS_DIR/)"
        missing=1
      else
        echo "  ✗ $mcp_name (not cloned; re-run ./install.sh)"
        missing=1
      fi
    done
  fi

  # Security tooling status — only if the skill is present
  if [[ -d "$REPO_DIR/skills/security-review-deep" ]]; then
    echo
    echo "Security tools (for security-review-deep):"
    local sec_missing=0
    # Core: needed for any run.
    for t in semgrep bandit gitleaks trufflehog trivy osv-scanner pip-audit uv; do
      if command -v "$t" >/dev/null 2>&1; then
        echo "  ✓ $t"
      else
        echo "  ✗ $t (run ./install.sh and choose to install security tools)"
        sec_missing=1
      fi
    done
    # CI / IaC / SBOM + memory-safety scanners. Missing here = the skill
    # silently skips that layer.
    for t in zizmor checkov hadolint shellcheck njsscan syft grype flawfinder cppcheck clang-tidy kube-score; do
      if command -v "$t" >/dev/null 2>&1; then
        echo "  ✓ $t"
      else
        echo "  - $t (optional; review skips this layer if absent)"
      fi
    done
    # Language toolchains: only relevant if you work in that language.
    for t in gosec govulncheck staticcheck brakeman cargo-audit cargo-geiger clippy-driver security-scan psalm; do
      if command -v "$t" >/dev/null 2>&1; then
        echo "  ✓ $t"
      fi
    done

    local mcp_dir="$REPO_DIR/skills/security-review-deep/mcp-server"
    if [[ -f "$mcp_dir/mcp_security_server.py" ]]; then
      if [[ -d "$mcp_dir/.venv" ]]; then
        echo "  ✓ MCP server venv"
      else
        echo "  ✗ MCP server venv not built"
        sec_missing=1
      fi
      if command -v claude >/dev/null 2>&1; then
        # Match either "security-advisories: ..." (default format) or
        # "Name: security-advisories" (some versions), anchored to start of line
        if claude mcp list 2>/dev/null | grep -qE "(^|[[:space:]])security-advisories[: ]"; then
          echo "  ✓ MCP registered with Claude Code"
        else
          echo "  ✗ MCP not registered (run ./install.sh and choose to install security tools)"
          sec_missing=1
        fi
      else
        echo "  ? claude CLI not on \$PATH — can't check MCP registration"
      fi
    fi
    [[ "$sec_missing" -ne 0 ]] && missing=1
  fi

  echo
  if [[ "$missing" -eq 0 ]]; then
    echo "All good."
    exit 0
  else
    echo "Some items missing. Re-run ./install.sh."
    exit 1
  fi
}

[[ "$CHECK_ONLY" -eq 1 ]] && run_check

# ---------------------------------------------------------------------------
# Symlink phase
# ---------------------------------------------------------------------------
echo "Installing from: $REPO_DIR"
echo "Target:          $CLAUDE_DIR"
echo

echo "Global config files:"
for name in CLAUDE.md userprofile.md style.md communication.md engineering.md settings.json; do
  if [[ -f "$REPO_DIR/$name" ]]; then
    link_file "$REPO_DIR/$name" "$CLAUDE_DIR/$name"
  fi
done

echo
echo "Skills:"
for skill_dir in "$REPO_DIR/skills"/*/; do
  [[ -d "$skill_dir" ]] || continue
  skill_name="$(basename "$skill_dir")"
  # Only treat as a skill if it contains a SKILL.md (skips containers like diffusion-skills/)
  if [[ -f "$skill_dir/SKILL.md" ]]; then
    link_file "${skill_dir%/}" "$CLAUDE_DIR/skills/$skill_name"
    if is_portable_skill "$skill_name"; then
      link_file "${skill_dir%/}" "$AGENTS_SKILLS_DIR/$skill_name"
    fi
  fi
done

# Custom sub-agents — flat .md files in agents/, symlinked into ~/.claude/agents/
if [[ -d "$REPO_DIR/agents" ]]; then
  echo
  echo "Agents:"
  for agent_file in "$REPO_DIR/agents"/*.md; do
    [[ -f "$agent_file" ]] || continue
    link_file "$agent_file" "$CLAUDE_DIR/agents/$(basename "$agent_file")"
  done
fi

prune_dangling "$CLAUDE_DIR/skills"
prune_dangling "$CLAUDE_DIR/agents"
prune_dangling "$AGENTS_SKILLS_DIR"

# ---------------------------------------------------------------------------
# Other agent CLIs (Codex, pi, opencode, Crush)
# ---------------------------------------------------------------------------
echo
echo "Other agent CLIs (Codex / pi / opencode / Crush):"
echo "  Portable skills linked into $AGENTS_SKILLS_DIR (Codex, pi, opencode read it natively)."
configure_crush_skills_path
write_flattened_rules "$CODEX_DIR/AGENTS.md" "global rules for Codex"
write_flattened_rules "$OPENCODE_DIR/AGENTS.md" "global rules for opencode"
echo "  note     pi has no global-rules file; it gets skills only (per-project AGENTS.md for rules)"

# ---------------------------------------------------------------------------
# Personal MCP servers (code only; registered per-project, not globally)
# ---------------------------------------------------------------------------
if [[ "${#PERSONAL_MCPS[@]}" -gt 0 ]]; then
  echo
  echo "Personal MCP servers (cloned to ~/mcps; inactive until registered per-project, see README):"
  mkdir -p "$MCPS_DIR"
  for entry in "${PERSONAL_MCPS[@]}"; do
    mcp_name="${entry%%|*}"
    mcp_url="${entry#*|}"
    mcp_path="$MCPS_DIR/$mcp_name"
    if [[ -d "$mcp_path/.git" ]]; then
      echo "  ok       $mcp_name ($mcp_path)"
      continue
    fi
    if [[ -d "$HOME/projects/$mcp_name/.git" ]]; then
      echo "  note     $mcp_name found at ~/projects/$mcp_name (old layout);"
      echo "           mv it to $mcp_path and update any local-scope registrations"
      continue
    fi
    if ask_yn "  Clone and sync $mcp_name?" Y; then
      echo "  clone    $mcp_name -> $mcp_path"
      if git clone --quiet "$mcp_url" "$mcp_path" && sync_mcp "$mcp_path"; then
        echo "  synced   $mcp_name"
      else
        echo "  fail     $mcp_name (clone/sync manually at $mcp_path)"
      fi
    else
      echo "  skip     $mcp_name (declined)"
    fi
  done
fi

# ---------------------------------------------------------------------------
# Security tools (opt-in, for the security-review-deep skill)
# ---------------------------------------------------------------------------
if [[ -d "$REPO_DIR/skills/security-review-deep" ]]; then
  echo
  if ask_yn "Install security-review-deep tools + advisories MCP?" N; then
    install_security_tools
  else
    echo "  skip     security tools (re-run ./install.sh to install later)"
  fi
fi

echo
echo "Done. Restart Claude Code if it was running, so it picks up changes."
echo "Run './install.sh --check' anytime to verify everything's wired up."
exit 0
