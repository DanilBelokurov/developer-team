#!/bin/bash
# DevTeam Qwen Code extension installer.
# Installs hooks and initializes state — everything qwen extension doesn't support.
#
# What qwen extension installs automatically:
#   - agents/, commands/, skills/ (via manifest)
#   - MCP servers (via mcpServers in qwen-extension.json)
#   - QWEN.md (via contextFileName)
#
# What install.sh handles:
#   - Lifecycle hooks (PreToolUse, PostToolUse, Stop, etc.)
#   - State initialization (.devteam/state/)
#   - Sentinel file (idempotency check)
#
# Supports project-level (via project-path argument) and user-level (default) install.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="${PLUGIN_DIR}/scripts"
CONFIG_FILE="${PLUGIN_DIR}/hooks/hooks-config.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[devteam]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[devteam]${NC} $1"; }
log_error() { echo -e "${RED}[devteam]${NC} $1" >&2; }

# ============================================================================
# USAGE
# ============================================================================

usage() {
    cat <<EOF
Usage: bash install.sh [project-path]

Installs DevTeam hooks and state into the target .qwen/ directory.

Note: agents, commands, skills, and MCP servers are installed automatically
      by 'qwen extensions install .'. This script handles only hooks and state.

Arguments:
  project-path    Optional path to a project. If provided, installs into
                  <project-path>/.qwen/. If omitted, auto-detects:
                  - inside git repo: <cwd>/.qwen/
                  - outside git repo: ~/.qwen/

Examples:
  bash install.sh                        # user-level install
  bash install.sh /path/to/myproject    # project-level install
EOF
}

# ============================================================================
# PREREQUISITES
# ============================================================================

echo ""
echo "Checking prerequisites..."

MISSING=()

command -v git     >/dev/null 2>&1 || MISSING+=("git")
command -v jq      >/dev/null 2>&1 || MISSING+=("jq")
command -v python3 >/dev/null 2>&1 || MISSING+=("python3")

if [ ${#MISSING[@]} -gt 0 ]; then
    log_error "missing required tools: ${MISSING[*]}"
    echo "  Install jq:       https://jqlang.github.io/jq/download/"
    echo "  Install python3:   https://www.python.org/downloads/"
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
JQ_VERSION=$(jq --version)
log_info "prerequisites OK (git, python${PYTHON_VERSION}, jq ${JQ_VERSION})"

# ============================================================================
# RESOLVE TARGET DIRECTORY
# ============================================================================

resolve_target() {
    local arg_path="$1"

    if [ -n "$arg_path" ]; then
        # Explicit path provided — user's intent
        echo "$(realpath "$arg_path")/.qwen"
        return
    fi

    # Auto-detect: inside git repo?
    if git -C . rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "$(pwd)/.qwen"
        return
    fi

    # Fallback: user-level
    echo "${HOME}/.qwen"
}

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

PROJECT_PATH="${1:-}"

if [ "${1:-}" == "--help" ] || [ "${1:-}" == "-h" ]; then
    usage
    exit 0
fi

TARGET="$(resolve_target "$PROJECT_PATH")"
SENTINEL="${TARGET}/.devteam-installed"

# .devteam/ location:
# - Project-level: <project>/.devteam/ (sibling to .qwen/)
# - User-level: ~/.qwen/.devteam/ (inside .qwen/)
if [ -n "$PROJECT_PATH" ]; then
    DEVTEAM_TARGET="$(realpath "$PROJECT_PATH")/.devteam"
else
    DEVTEAM_TARGET="${TARGET}/.devteam"
fi

# ============================================================================
# IDEMPOTENCY CHECK
# ============================================================================

if [ -f "$SENTINEL" ]; then
    log_info "already installed at ${TARGET} — run 'bash uninstall.sh${PROJECT_PATH:+ $PROJECT_PATH}' first to reinstall"
    exit 0
fi

# ============================================================================
# MCP SERVER PREREQUISITES (warn-only)
# ============================================================================

echo ""
echo "Checking MCP server prerequisites..."
if ! command -v npx >/dev/null 2>&1; then
    log_warn "npx (Node.js) not found — github and memory MCP servers will be unavailable"
    log_warn "  Install Node.js from https://nodejs.org/"
else
    log_info "MCP prerequisites OK (npx found)"
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
    log_warn "GITHUB_TOKEN not set — github MCP server will be unavailable"
else
    log_info "GITHUB_TOKEN is set"
fi

# ============================================================================
# CREATE TARGET DIRECTORY
# ============================================================================

log_info "target: ${TARGET}"
mkdir -p "${TARGET}"

# ============================================================================
# COPY HOOKS TO .devteam/hooks/
# ============================================================================

echo ""
echo "Installing hooks into ${DEVTEAM_TARGET}/hooks/..."

mkdir -p "${DEVTEAM_TARGET}"
rm -rf "${DEVTEAM_TARGET}/hooks"
cp -r "${PLUGIN_DIR}/hooks" "${DEVTEAM_TARGET}/hooks"

count_hooks=$(find "${DEVTEAM_TARGET}/hooks" -name '*.sh' -o -name '*.js' -o -name '*.ps1' 2>/dev/null | wc -l | tr -d ' ')
log_info "  hooks/ — ${count_hooks} scripts"

# ============================================================================
# MERGE HOOKS INTO settings.json
# ============================================================================

echo ""
echo "Installing hooks into ${TARGET}/settings.json..."

# Substitute __HOOK_BASE__ placeholder with absolute path
# Use perl for cross-platform sed compatibility (macOS sed doesn't handle / in paths well)
# Use SINGLE quotes for regex + variable outside to handle @ in paths
HOOK_PATH="${DEVTEAM_TARGET}/hooks"
HOOK_CONFIG="$(perl -pe 's|__HOOK_BASE__|'"${HOOK_PATH}"'|g' "$CONFIG_FILE")"

if [ ! -f "${TARGET}/settings.json" ]; then
    echo "$HOOK_CONFIG" > "${TARGET}/settings.json"
    log_info "created ${TARGET}/settings.json"
else
    tmp_file="$(mktemp)"
    trap "rm -f '$tmp_file'" EXIT

    # Handle empty settings.json by treating it as {}
    EXISTING_CONFIG="$(cat "${TARGET}/settings.json")"
    if [ -z "$EXISTING_CONFIG" ]; then
        EXISTING_CONFIG="{}"
    fi

    jq --argjson newcfg "$HOOK_CONFIG" --argjson existing "$EXISTING_CONFIG" '
      def deep_merge($a; $b):
        if ($a | type) == "object" and ($b | type) == "object" then
          ($a | keys) as $akeys | ($b | keys) as $bkeys |
          ($akeys + $bkeys | unique) as $allkeys |
          $allkeys | map(
            . as $k |
            if ($a | has($k)) and ($b | has($k)) then
              {key: $k, value: deep_merge($a[$k]; $b[$k])}
            elif ($a | has($k)) then
              {key: $k, value: $a[$k]}
            else
              {key: $k, value: $b[$k]}
            end
          ) | from_entries
        else
          ($b // $a)
        end;
      deep_merge($existing; $newcfg)
    ' <<< '{}' > "$tmp_file"

    mv "$tmp_file" "${TARGET}/settings.json"
    log_info "merged hooks into ${TARGET}/settings.json"
fi

# ============================================================================
# INITIALIZE STATE
# ============================================================================

echo ""
echo "Initializing state..."
# Project-level: .devteam/ lives next to .qwen/ (sibling layout)
# User-level: .devteam/ lives inside .qwen/ (TARGET is ~/.qwen)
if [ -n "$PROJECT_PATH" ]; then
    STATE_ROOT="$PROJECT_PATH"
else
    STATE_ROOT="$TARGET"
fi
bash "${SCRIPT_DIR}/state-init.sh" "${STATE_ROOT}"

# ============================================================================
# CREATE SENTINEL
# ============================================================================

echo ""
echo "Creating sentinel..."
date +%Y-%m-%dT%H:%M:%S > "$SENTINEL"
echo "${TARGET}" >> "$SENTINEL"
log_info "created ${SENTINEL}"

# ============================================================================
# DONE
# ============================================================================

echo ""
echo "Installation complete!"
echo ""
echo "  Target:      ${TARGET}"
echo "  Hooks:       ${DEVTEAM_TARGET}/hooks/"
echo "  Settings:    ${TARGET}/settings.json"
echo "  State:       ${DEVTEAM_TARGET}/state/"
echo ""
echo "Note: agents/, commands/, skills/ are installed via 'qwen extensions install .'"
echo ""
echo "Next steps:"
echo "  1. Restart Qwen Code to load the extension"
echo "  2. Verify: /skills (should show devteam skills)"
echo "  3. Verify: /agents manage (should show subagents)"
echo "  4. Verify: /devteam:status"
echo "  5. (Optional) Set GITHUB_TOKEN for GitHub MCP integration"
