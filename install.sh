#!/usr/bin/env bash
# Copy this repo's Claude Code config files into ~/.claude/ so the same
# CLAUDE.md, userprofile.md, style.md, communication.md, engineering.md,
# skills, and sub-agents are active wherever the repo is cloned. Copies (not
# symlinks) keep ~/.claude decoupled from where the repo lives — move or rename
# the repo and the config keeps working; re-run after a `git pull` to apply
# updates (same model as the MCPs). A changed real file at a target path is
# backed up to ~/.claude/<name>.backup-YYYYMMDD-HHMMSS before being replaced.
#
# Portable skills (no Claude-Code sub-agent / MCP dependency) are ALSO copied
# into ~/.agents/skills/ so Codex, pi, and opencode pick them up; Crush is
# pointed at the same dir via skills_paths in its crush.json. The global rules
# (userprofile/style/communication/engineering) are concatenated into
# ~/.codex/AGENTS.md, since non-Claude agents don't resolve CLAUDE.md @imports.
#
# Config files and skills install non-interactively. The script then prompts,
# once each, to clone any personal MCP repos (PERSONAL_MCPS, into ~/mcps/,
# registered per-project with `claude mcp add --scope local`, see README), to
# clone personal repos for editing (PERSONAL_REPOS, into ~/projects/), and to
# install the security-review-deep tools. With no terminal attached it takes
# each prompt's default and does not block.
#
# Re-runnable. Unchanged files and already-cloned repos are left as-is.
#
# Usage:
#   ./install.sh          # config + skills, then prompt for MCPs and security tools
#   ./install.sh --config-only  # config + skills + cross-agent rules; no MCP/repo cloning
#   ./install.sh --check  # verify install + report missing tools
#   ./install.sh --help   # show this usage

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Target dirs are env-overridable so the same install can be aimed at a temp
# tree (used by tests/ to diff legacy placement against the generator).
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
STAMP="$(date +%Y%m%d-%H%M%S)"

# Cross-agent skill dir read natively by Codex, pi, and opencode, and by Crush
# via skills_paths. Only skills in PORTABLE_SKILLS land here.
AGENTS_SKILLS_DIR="${AGENTS_SKILLS_DIR:-$HOME/.agents/skills}"
CODEX_DIR="${CODEX_DIR:-$HOME/.codex}"
OPENCODE_DIR="${OPENCODE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"

# Which accelerated backend extras this machine can use. Apple Silicon -> mlx,
# an NVIDIA box -> cuda, anything else -> cpu. Drives the per-capability `uv`
# extras in PERSONAL_MCPS so e.g. transcribemcp gets cohere-mlx on the Mac and a
# CUDA torch on the 4090 without per-machine hand-editing.
detect_compute() {
  if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]]; then
    echo mlx
  elif command -v nvidia-smi >/dev/null 2>&1; then
    echo cuda
  else
    echo cpu
  fi
}
COMPUTE_CAP="$(detect_compute)"

# Skills with no Claude-Code-specific machinery (no spawned sub-agents, no
# bundled MCP server) — safe to expose to other agent CLIs. The heavy skills
# (code-review-deep, deep-planner, writing-architect, security-review-deep,
# llm-council) stay Claude-only: their SKILL.md would load elsewhere but then
# half-execute.
PORTABLE_SKILLS=(
  bug-hunter
  doc-grounded
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
CONFIG_ONLY=0

# Personal MCP servers to make available on this machine. For each, the script
# clones to ~/mcps/<name>, `git pull`s an existing clone, runs `uv sync` (with
# any per-machine extras), seeds a .env from .env.example, and writes a launch
# wrapper to ~/mcps/bin/<name>-run. It does NOT register them with any client,
# so they stay inactive until you point Claude Code (`claude mcp add --scope
# local`, see README) or Goose (add a stdio extension whose command is the
# wrapper) at the wrapper.
#
# Format: "name|git-url[|entrypoint][|CAP=extra,extra]..."
#   entrypoint  the uv script to run (defaults to the MCP name)
#   CAP=...     uv extras to sync for that machine class; CAP is mlx|cuda|cpu
#               (see detect_compute). Omit a CAP to sync base deps only there.
MCPS_DIR="$HOME/mcps"
WRAPPER_DIR="$MCPS_DIR/bin"
PERSONAL_MCPS=(
  "edamcp|https://github.com/charliecpeterson/edamcp.git"
  "chemtoolsmcp|https://github.com/charliecpeterson/chemtoolsmcp.git"
  "comfyui_mcp|https://github.com/charliecpeterson/comfyui_mcp.git"
  "office-google-mac-mcp|https://github.com/charliecpeterson/office-google-mac-mcp.git"
  "h2mcp|https://github.com/charliecpeterson/h2mcp.git"
  # transcribemcp: thin local transcription MCP (audio in, transcript JSON out).
  # whisperx backend + pyannote diarization => whisperx,diarize. The vad extra
  # (silero-vad) is only strictly needed for TRANSCRIPTION_BACKEND=cohere, which
  # has no native timestamps; kept here so a backend swap needs no re-sync.
  # ctranslate2 has no Metal backend, so whisperx runs on CPU on Apple Silicon
  # (cuda on the 4090). Swap in cohere,cohere-mlx,vad,diarize here if you set
  # TRANSCRIPTION_BACKEND=cohere for MLX-accelerated transcription on the Mac.
  # Entrypoint defaults to the name (transcribemcp), so it's omitted below.
  "transcribemcp|https://github.com/charliecpeterson/transcribemcp.git|mlx=whisperx,vad,diarize|cuda=whisperx,vad,diarize|cpu=whisperx,vad,diarize"
)

# Personal repos to have on hand for editing. Plain `git clone` (no build step),
# unlike the MCPs above — these are workspaces you edit. Cloned to ~/projects/<name>.
# The presentation template is also a GitHub *template* repo: start a new talk with
# `gh repo create my-talk --template charliecpeterson/presentation-template`, not
# from this clone — this clone is only for editing the template itself.
# Format: "name|git-url".
REPOS_DIR="$HOME/projects"
PERSONAL_REPOS=(
  "presentation-template|https://github.com/charliecpeterson/presentation-template.git"
)

# Parse a PERSONAL_MCPS entry. Fields split on '|': 0=name 1=git-url, then an
# optional bare entrypoint token and any number of CAP=extra,extra tokens.
mcp_field() { local -a f; IFS='|' read -ra f <<< "$1"; printf '%s' "${f[$2]:-}"; }

mcp_entrypoint() {
  local -a f; local tok ep
  IFS='|' read -ra f <<< "$1"; ep="${f[0]}"
  if [[ ${#f[@]} -gt 2 ]]; then
    for tok in "${f[@]:2}"; do [[ "$tok" != *=* ]] && ep="$tok"; done
  fi
  printf '%s' "$ep"
}

# uv extras to sync for THIS machine ($COMPUTE_CAP), or empty.
mcp_extras() {
  local -a f; local tok
  IFS='|' read -ra f <<< "$1"
  if [[ ${#f[@]} -gt 2 ]]; then
    for tok in "${f[@]:2}"; do
      [[ "$tok" == "$COMPUTE_CAP="* ]] && { printf '%s' "${tok#*=}"; return; }
    done
  fi
}

# Build a freshly cloned MCP: uv for Python repos (with any per-machine extras),
# npm (+ build script if one exists) for node repos.
sync_mcp() {
  local path="$1" extras="${2:-}" name e
  local -a extra_args=()
  name="$(basename "$path")"
  if [[ -f "$path/pyproject.toml" ]]; then
    if ! command -v uv >/dev/null 2>&1; then
      echo "  manual   $name: install uv, then run 'uv sync' in $path"
      return 1
    fi
    if [[ -n "$extras" ]]; then
      local IFS=','
      for e in $extras; do extra_args+=(--extra "$e"); done
    fi
    if [[ ${#extra_args[@]} -gt 0 ]]; then
      (cd "$path" && uv sync --quiet "${extra_args[@]}")
    else
      (cd "$path" && uv sync --quiet)
    fi
  elif [[ -f "$path/package.json" ]]; then
    if ! command -v npm >/dev/null 2>&1; then
      echo "  manual   $name: install node, then 'npm install && npm run build' in $path"
      return 1
    fi
    (cd "$path" && npm install --silent \
      && { ! grep -q '"build"' package.json || npm run --silent build; })
  fi
}

# Seed a gitignored .env from .env.example so per-machine secrets/config live in
# one file the server loads itself (pydantic-settings / dotenv) instead of being
# re-entered in every client. Never overwrites an existing .env; values still
# need filling in by hand.
seed_env_file() {
  local path="$1" name="$2"
  [[ -f "$path/.env.example" ]] || return 0
  if [[ -f "$path/.env" ]]; then
    echo "  ok       $name/.env present"
  else
    cp "$path/.env.example" "$path/.env"
    echo "  env      $name/.env created from .env.example — fill in secrets"
  fi
}

# One launch command per MCP, with this machine's extras baked in. Point every
# client (Claude Code, Goose, …) at this path; re-running install.sh refreshes it
# after a hardware or backend change. uv-only; node MCPs launch differently.
write_mcp_wrapper() {
  local name="$1" path="$2" entrypoint="$3" extras="$4" e extra_flags=""
  [[ -f "$path/pyproject.toml" ]] || return 0
  mkdir -p "$WRAPPER_DIR"
  if [[ -n "$extras" ]]; then
    local IFS=','
    for e in $extras; do extra_flags="$extra_flags --extra $e"; done
  fi
  local wrapper="$WRAPPER_DIR/${name}-run"
  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
# Generated by claude-config install.sh — launch wrapper for the $name MCP.
# Machine class: $COMPUTE_CAP. Point every client at this path; re-run install.sh
# to refresh extras after a hardware or backend change.
exec uv --directory "$path" run$extra_flags $entrypoint "\$@"
EOF
  chmod +x "$wrapper"
  echo "  wrapper  $wrapper"
}

# A cloned MCP counts as ready only once its deps are built. Otherwise a
# clone that succeeded but whose sync failed (e.g. uv/npm was missing)
# would re-report "ok" on every run and never repair itself.
mcp_is_synced() {
  local path="$1"
  if [[ -f "$path/pyproject.toml" ]]; then
    [[ -d "$path/.venv" ]]
  elif [[ -f "$path/package.json" ]]; then
    [[ -d "$path/node_modules" ]]
  else
    return 0
  fi
}

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --config-only) CONFIG_ONLY=1 ;;
    -h|--help)
      sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
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
# Agents are instructed (style.md) to put scratch output here, not /tmp.
mkdir -p "$HOME/scratch"

# Copy (not symlink) repo content into place. Copies decouple the installed
# config from where this repo lives: you can move/rename/relocate the repo and
# ~/.claude keeps working until you next run. Re-running after a `git pull` is
# how you apply updates — the same model the MCPs already use. Unchanged targets
# are left untouched (idempotent no-op); a changed real file is backed up before
# it's replaced. A leftover symlink from the old install model is replaced with
# a real copy.
_same_content() {
  local a="$1" b="$2"
  if [[ -d "$a" ]]; then
    diff -rq "$a" "$b" >/dev/null 2>&1
  else
    cmp -s "$a" "$b"
  fi
}

place_file() {
  local src="$1" dest="$2"
  if [[ -L "$dest" ]]; then
    rm "$dest"
    echo "  copy     $dest (was symlink)"
  elif [[ -e "$dest" ]]; then
    if _same_content "$src" "$dest"; then
      echo "  ok       $dest"
      return
    fi
    local backup="${dest}.backup-${STAMP}"
    echo "  backup   $dest -> $backup"
    rm -rf "$backup"
    mv "$dest" "$backup"
  else
    echo "  new      $dest"
  fi
  mkdir -p "$(dirname "$dest")"
  cp -R "$src" "$dest"
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

# (AGENTS.md flattening for Codex/opencode moved into the agentconfig
# generator's per-harness adapters; Crush/pi adapters are still to come.)

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

  if [[ -d "$REPO_DIR/hooks" ]]; then
    echo
    echo "Hooks:"
    if [[ -L "$CLAUDE_DIR/hooks" ]] && [[ "$(readlink "$CLAUDE_DIR/hooks")" == "$REPO_DIR/hooks" ]]; then
      echo "  ✓ ~/.claude/hooks -> repo (statusline + $(find "$REPO_DIR/hooks" -name '*.sh' | wc -l | tr -d ' ') scripts)"
    else
      echo "  ✗ ~/.claude/hooks not linked to repo (re-run ./install.sh)"
      missing=1
    fi
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
        if mcp_is_synced "$MCPS_DIR/$mcp_name"; then
          echo "  ✓ $mcp_name"
        else
          echo "  ✗ $mcp_name (cloned but not built; re-run ./install.sh)"
          missing=1
        fi
      elif [[ -d "$HOME/projects/$mcp_name/.git" ]]; then
        echo "  ✗ $mcp_name (at ~/projects/$mcp_name, old layout; mv to $MCPS_DIR/)"
        missing=1
      else
        echo "  ✗ $mcp_name (not cloned; re-run ./install.sh)"
        missing=1
      fi
    done
  fi

  if [[ "${#PERSONAL_REPOS[@]}" -gt 0 ]]; then
    echo
    echo "Personal repos (~/projects):"
    for entry in "${PERSONAL_REPOS[@]}"; do
      local repo_name="${entry%%|*}"
      if [[ -d "$REPOS_DIR/$repo_name/.git" ]]; then
        echo "  ✓ $repo_name"
      else
        echo "  ✗ $repo_name (not cloned; re-run ./install.sh)"
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

# Find a python3 with tomllib (>=3.11) for the generator.
_find_python() {
  local p
  for p in python3 python3.14 python3.13 python3.12 python3.11; do
    command -v "$p" >/dev/null 2>&1 || continue
    "$p" -c 'import tomllib' 2>/dev/null && { echo "$p"; return 0; }
  done
  return 1
}

# ---------------------------------------------------------------------------
# Config phase
# ---------------------------------------------------------------------------
echo "Installing from: $REPO_DIR"
echo "Target:          $CLAUDE_DIR"
echo

# Claude config (rules, skills, sub-agents, hooks) is rendered by the Python
# generator (agentconfig), which copies into $CLAUDE_DIR. The legacy bash
# placement it replaced is verified byte-identical by tests/test_golden.py.
echo "Claude config (via agentconfig generator):"
if py="$(_find_python)"; then
  CLAUDE_DIR="$CLAUDE_DIR" PYTHONPATH="$REPO_DIR" $py -m agentconfig --repo-root "$REPO_DIR" \
    || echo "  warn     generator reported failures (see above)"
else
  echo "  manual   need python3 >=3.11 (tomllib) to render Claude config; install it and re-run"
fi

# Cross-agent skills export — portable skills also copied to ~/.agents/skills
# for Codex/pi/opencode. (Moves into per-harness adapters in Phase 2.)
echo
echo "Cross-agent skills (~/.agents/skills):"
for skill_dir in "$REPO_DIR/skills"/*/; do
  [[ -d "$skill_dir" ]] || continue
  skill_name="$(basename "$skill_dir")"
  if [[ -f "$skill_dir/SKILL.md" ]] && is_portable_skill "$skill_name"; then
    place_file "${skill_dir%/}" "$AGENTS_SKILLS_DIR/$skill_name"
  fi
done

prune_dangling "$AGENTS_SKILLS_DIR"

# ---------------------------------------------------------------------------
# Other agent CLIs (Codex, pi, opencode, Crush)
# ---------------------------------------------------------------------------
echo
echo "Other agent CLIs (Codex / pi / opencode / Crush):"
echo "  Portable skills copied into $AGENTS_SKILLS_DIR (pi, opencode read it natively;"
echo "  Codex registers skill paths in config.toml instead — handled by the generator)."
configure_crush_skills_path
# Codex and opencode AGENTS.md + MCP are now rendered by the agentconfig
# generator (their adapters). Crush + pi adapters are still to come.
echo "  note     Codex/opencode rules+MCP via the generator; pi gets skills only"

# Config-only stops here: skip MCP/repo cloning + security tools. Useful after a
# `git pull` to apply config changes without touching the MCP venvs.
if [[ "$CONFIG_ONLY" -eq 1 ]]; then
  echo
  echo "config-only: skipping MCP/repo cloning and security tools."
  exit 0
fi

# ---------------------------------------------------------------------------
# Personal MCP servers (code only; registered per-project, not globally)
# ---------------------------------------------------------------------------
if [[ "${#PERSONAL_MCPS[@]}" -gt 0 ]]; then
  echo
  echo "Personal MCP servers (cloned to ~/mcps; machine class: $COMPUTE_CAP; inactive until a client points at ~/mcps/bin/<name>-run, see README):"
  mkdir -p "$MCPS_DIR"
  for entry in "${PERSONAL_MCPS[@]}"; do
    mcp_name="$(mcp_field "$entry" 0)"
    mcp_url="$(mcp_field "$entry" 1)"
    mcp_ep="$(mcp_entrypoint "$entry")"
    mcp_ex="$(mcp_extras "$entry")"
    mcp_path="$MCPS_DIR/$mcp_name"
    if [[ -d "$mcp_path/.git" ]]; then
      if git -C "$mcp_path" pull --ff-only --quiet 2>/dev/null; then
        echo "  pull     $mcp_name (fresh)"
      else
        echo "  note     $mcp_name: git pull skipped (local changes or non-ff; resolve at $mcp_path)"
      fi
      if sync_mcp "$mcp_path" "$mcp_ex"; then
        echo "  synced   $mcp_name${mcp_ex:+ [$COMPUTE_CAP: $mcp_ex]}"
      else
        echo "  fail     $mcp_name (sync manually at $mcp_path)"
      fi
      seed_env_file "$mcp_path" "$mcp_name"
      write_mcp_wrapper "$mcp_name" "$mcp_path" "$mcp_ep" "$mcp_ex"
      continue
    fi
    if [[ -d "$HOME/projects/$mcp_name/.git" ]]; then
      echo "  note     $mcp_name found at ~/projects/$mcp_name (old layout);"
      echo "           mv it to $mcp_path and update any local-scope registrations"
      continue
    fi
    if ask_yn "  Clone and sync $mcp_name?" Y; then
      echo "  clone    $mcp_name -> $mcp_path"
      if git clone --quiet "$mcp_url" "$mcp_path" && sync_mcp "$mcp_path" "$mcp_ex"; then
        echo "  synced   $mcp_name${mcp_ex:+ [$COMPUTE_CAP: $mcp_ex]}"
        seed_env_file "$mcp_path" "$mcp_name"
        write_mcp_wrapper "$mcp_name" "$mcp_path" "$mcp_ep" "$mcp_ex"
      else
        echo "  fail     $mcp_name (clone/sync manually at $mcp_path)"
      fi
    else
      echo "  skip     $mcp_name (declined)"
    fi
  done
fi

# ---------------------------------------------------------------------------
# Personal repos (plain clones you edit; e.g. the presentation template)
# ---------------------------------------------------------------------------
if [[ "${#PERSONAL_REPOS[@]}" -gt 0 ]]; then
  echo
  echo "Personal repos (cloned to ~/projects for editing):"
  mkdir -p "$REPOS_DIR"
  for entry in "${PERSONAL_REPOS[@]}"; do
    repo_name="${entry%%|*}"
    repo_url="${entry#*|}"
    repo_path="$REPOS_DIR/$repo_name"
    if [[ -d "$repo_path/.git" ]]; then
      echo "  ok       $repo_name ($repo_path)"
      continue
    fi
    if ask_yn "  Clone $repo_name?" Y; then
      echo "  clone    $repo_name -> $repo_path"
      if git clone --quiet "$repo_url" "$repo_path"; then
        echo "  cloned   $repo_name"
      else
        echo "  fail     $repo_name (clone manually at $repo_path)"
      fi
    else
      echo "  skip     $repo_name (declined)"
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
