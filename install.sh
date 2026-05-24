#!/usr/bin/env bash
# Symlink this repo's Claude Code config files into ~/.claude/ so the same
# CLAUDE.md, style.md, communication.md, and skills are active wherever the
# repo is cloned. Existing files (not already symlinks pointing into this
# repo) are backed up to ~/.claude/<name>.backup-YYYYMMDD-HHMMSS first.
#
# Re-runnable. Skips files that are already correctly symlinked.
#
# Also clones the personal MCP repos in PERSONAL_MCPS to ~/projects/ and runs
# `uv sync`, but does not register them with Claude Code. Register those
# per-project with `claude mcp add --scope local` (see README) so their tools
# only load where you use them.
#
# Usage:
#   ./install.sh                        # symlinks only (default, fast)
#   ./install.sh --with-security-tools  # also install scanners + MCP server
#                                       # for the security-review-deep skill
#   ./install.sh --check                # verify install + report missing tools
#   ./install.sh --help                 # show usage

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
STAMP="$(date +%Y%m%d-%H%M%S)"

WITH_SECURITY=0
CHECK_ONLY=0

# Personal MCP servers to make available on this machine. The script clones
# each to ~/projects/<name> and runs `uv sync`; it does NOT register them with
# Claude Code. Register per-project with `claude mcp add --scope local` (see
# README) so their tools only load where you actually use them.
# Format: "name|git-url".
PERSONAL_MCPS=(
  "edamcp|https://github.com/charliecpeterson/edamcp.git"
)

for arg in "$@"; do
  case "$arg" in
    --with-security-tools) WITH_SECURITY=1 ;;
    --check) CHECK_ONLY=1 ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
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

# ---------------------------------------------------------------------------
# Doctor / --check mode
# ---------------------------------------------------------------------------
run_check() {
  local missing=0
  echo "Repo:    $REPO_DIR"
  echo "Target:  $CLAUDE_DIR"
  echo

  echo "Synced files:"
  for name in CLAUDE.md style.md communication.md engineering.md; do
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
      echo "  ✓ $(basename "$link")"
      ((n++)) || true
    fi
  done
  [[ "$n" -eq 0 ]] && { echo "  (none)"; missing=1; }

  if [[ "${#PERSONAL_MCPS[@]}" -gt 0 ]]; then
    echo
    echo "Personal MCP repos (~/projects; register per-project, see README):"
    for entry in "${PERSONAL_MCPS[@]}"; do
      local mcp_name="${entry%%|*}"
      if [[ -d "$HOME/projects/$mcp_name/.git" ]]; then
        echo "  ✓ $mcp_name"
      else
        echo "  ✗ $mcp_name (not cloned — re-run ./install.sh)"
        missing=1
      fi
    done
  fi

  # Security tooling status — only if the skill is present
  if [[ -d "$REPO_DIR/skills/security-review-deep" ]]; then
    echo
    echo "Security tools (for security-review-deep):"
    local sec_missing=0
    for t in semgrep bandit gitleaks trivy osv-scanner pip-audit uv; do
      if command -v "$t" >/dev/null 2>&1; then
        echo "  ✓ $t"
      else
        echo "  ✗ $t (run: ./install.sh --with-security-tools)"
        sec_missing=1
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
        # "Name: security-advisories" (some versions) — anchored to start of line
        if claude mcp list 2>/dev/null | grep -qE "(^|[[:space:]])security-advisories[: ]"; then
          echo "  ✓ MCP registered with Claude Code"
        else
          echo "  ✗ MCP not registered (run: ./install.sh --with-security-tools)"
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
    echo "Some items missing. Re-run ./install.sh (add --with-security-tools if needed)."
    exit 1
  fi
}

[[ "$CHECK_ONLY" -eq 1 ]] && run_check

# ---------------------------------------------------------------------------
# Symlink phase (the existing behavior, unchanged)
# ---------------------------------------------------------------------------
echo "Installing from: $REPO_DIR"
echo "Target:          $CLAUDE_DIR"
echo

echo "Global config files:"
for name in CLAUDE.md style.md communication.md engineering.md; do
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
  fi
done

# Diffusion skills live one level deeper: skills/diffusion-skills/skills/<name>/
if [[ -d "$REPO_DIR/skills/diffusion-skills/skills" ]]; then
  echo
  echo "Diffusion skills:"
  for skill_dir in "$REPO_DIR/skills/diffusion-skills/skills"/*/; do
    [[ -d "$skill_dir" ]] || continue
    skill_name="$(basename "$skill_dir")"
    if [[ -f "$skill_dir/SKILL.md" ]]; then
      link_file "${skill_dir%/}" "$CLAUDE_DIR/skills/$skill_name"
    fi
  done
fi

# ---------------------------------------------------------------------------
# Personal MCP servers (code only; registered per-project, not globally)
# ---------------------------------------------------------------------------
if [[ "${#PERSONAL_MCPS[@]}" -gt 0 ]]; then
  echo
  echo "Personal MCP servers (cloned to ~/projects; register per-project, see README):"
  if command -v uv >/dev/null 2>&1; then
    for entry in "${PERSONAL_MCPS[@]}"; do
      mcp_name="${entry%%|*}"
      mcp_url="${entry#*|}"
      mcp_path="$HOME/projects/$mcp_name"
      if [[ -d "$mcp_path/.git" ]]; then
        echo "  ok       $mcp_name ($mcp_path)"
      else
        echo "  clone    $mcp_name -> $mcp_path"
        if git clone --quiet "$mcp_url" "$mcp_path" && (cd "$mcp_path" && uv sync --quiet); then
          echo "  synced   $mcp_name"
        else
          echo "  fail     $mcp_name — clone/sync manually at $mcp_path"
        fi
      fi
    done
  else
    echo "  skip     uv not found; install uv, then re-run"
  fi
fi

# ---------------------------------------------------------------------------
# Security tools phase (opt-in)
# ---------------------------------------------------------------------------
if [[ "$WITH_SECURITY" -eq 1 ]]; then
  if [[ ! -d "$REPO_DIR/skills/security-review-deep" ]]; then
    echo
    echo "Note: --with-security-tools requested but skills/security-review-deep/ is not in this repo. Skipping."
  else
    echo
    echo "Security tools:"

    install_pkg() {
      # install_pkg <command-name> [brew-name]
      local cmd="$1" brew_name="${2:-$1}"
      if command -v "$cmd" >/dev/null 2>&1; then
        echo "  ok       $cmd already installed"
        return
      fi
      if [[ "$OSTYPE" == "darwin"* ]] && command -v brew >/dev/null 2>&1; then
        echo "  install  $cmd (brew)"
        brew install "$brew_name" >/dev/null 2>&1 || {
          echo "  fail     $cmd — try: brew install $brew_name"
        }
      else
        echo "  skip     $cmd (no brew on this system; install manually)"
      fi
    }

    install_pipx_pkg() {
      local pkg="$1"
      if command -v "$pkg" >/dev/null 2>&1; then
        echo "  ok       $pkg already installed"
        return
      fi
      if ! command -v pipx >/dev/null 2>&1; then
        install_pkg pipx
        command -v pipx >/dev/null 2>&1 && pipx ensurepath >/dev/null 2>&1 || true
      fi
      if command -v pipx >/dev/null 2>&1; then
        echo "  install  $pkg (pipx)"
        pipx install "$pkg" >/dev/null 2>&1 || echo "  fail     $pkg — try: pipx install $pkg"
      else
        echo "  skip     $pkg (pipx not available)"
      fi
    }

    # Native binaries
    install_pkg semgrep
    install_pkg gitleaks
    install_pkg trivy
    install_pkg osv-scanner
    install_pkg uv

    # Python scanners via pipx (avoids externally-managed-environment errors)
    install_pipx_pkg bandit
    install_pipx_pkg pip-audit

    # MCP server setup
    MCP_DIR="$REPO_DIR/skills/security-review-deep/mcp-server"
    if [[ -f "$MCP_DIR/mcp_security_server.py" ]]; then
      echo
      echo "MCP server (security-advisories):"
      if [[ -d "$MCP_DIR/.venv" ]]; then
        echo "  ok       venv exists at $MCP_DIR/.venv"
      elif command -v uv >/dev/null 2>&1; then
        echo "  build    uv venv + install at $MCP_DIR"
        (cd "$MCP_DIR" && uv venv >/dev/null 2>&1 && uv pip install -e . >/dev/null 2>&1) \
          || echo "  fail     uv venv/install — try manually in $MCP_DIR"
      else
        echo "  skip     uv not available; install uv and re-run"
      fi

      # Register with Claude Code if not already
      if command -v claude >/dev/null 2>&1; then
        if claude mcp list 2>/dev/null | grep -qE "(^|[[:space:]])security-advisories[: ]"; then
          echo "  ok       MCP already registered as 'security-advisories' (user scope)"
        elif [[ -x "$MCP_DIR/.venv/bin/python" ]]; then
          echo "  register MCP server with Claude Code (user scope)"
          if mcp_err=$(claude mcp add --scope user security-advisories \
              -- "$MCP_DIR/.venv/bin/python" "$MCP_DIR/mcp_security_server.py" 2>&1); then
            echo "  ok       registered"
          else
            echo "  fail     claude mcp add returned:"
            echo "$mcp_err" | sed 's/^/             /'
            echo "           register manually with:"
            echo "             claude mcp add --scope user security-advisories -- \\"
            echo "               $MCP_DIR/.venv/bin/python $MCP_DIR/mcp_security_server.py"
          fi
        else
          echo "  skip     MCP venv not built yet; can't register"
        fi
      else
        echo "  skip     claude CLI not on \$PATH — register MCP manually later:"
        echo "           claude mcp add --scope user security-advisories -- \\"
        echo "             $MCP_DIR/.venv/bin/python $MCP_DIR/mcp_security_server.py"
      fi
    fi

    cat <<'EOF'

Optional: set these env vars in your shell profile for higher API rate limits:
  export GITHUB_TOKEN="ghp_..."   # any classic token, no scopes needed
  export NVD_API_KEY="..."        # free at nvd.nist.gov/developers/request-an-api-key
EOF
  fi
fi

echo
echo "Done. Restart Claude Code if it was running, so it picks up changes."
[[ "$WITH_SECURITY" -eq 1 ]] && echo "Run './install.sh --check' anytime to verify everything's wired up."
exit 0
