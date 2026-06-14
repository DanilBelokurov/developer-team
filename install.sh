#!/bin/bash
# DevTeam Qwen Code extension installer.
# Installs hooks into ~/.qwen/settings.json and copies agents/commands/skills to ~/.qwen/.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="${PLUGIN_DIR}/hooks"
CONFIG_FILE="${PLUGIN_DIR}/hooks/hooks-config.json"
QWEN_SETTINGS="${HOME}/.qwen/settings.json"
SENTINEL="${HOME}/.qwen/.devteam-installed"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[devteam]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[devteam]${NC} $1"; }
log_error() { echo -e "${RED}[devteam]${NC} $1" >&2; }

# ============================================================================
# PREREQUISITES
# ============================================================================

echo ""
echo "Checking prerequisites..."

MISSING=()

command -v git    >/dev/null 2>&1 || MISSING+=("git")
command -v jq     >/dev/null 2>&1 || MISSING+=("jq")
command -v python3>/dev/null 2>&1 || MISSING+=("python3")

if [ ${#MISSING[@]} -gt 0 ]; then
    log_error "missing required tools: ${MISSING[*]}"
    echo "  Install jq:  https://jqlang.github.io/jq/download/"
    echo "  Install python3: https://www.python.org/downloads/"
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
JQ_VERSION=$(jq --version)
log_info "prerequisites OK (git, python${PYTHON_VERSION}, jq ${JQ_VERSION})"

# ============================================================================
# IDEMPOTENCY CHECK
# ============================================================================

if [ -f "$SENTINEL" ]; then
    log_info "already installed — run 'bash uninstall.sh' first to reinstall"
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
# ENSURE ~/.qwen EXISTS
# ============================================================================

mkdir -p "${HOME}/.qwen"

# ============================================================================
# MERGE HOOKS INTO settings.json
# ============================================================================

echo ""
echo "Installing hooks into ${QWEN_SETTINGS}..."

if [ ! -f "$QWEN_SETTINGS" ]; then
    # No existing config — just write hooks
    cp "$CONFIG_FILE" "$QWEN_SETTINGS"
    log_info "created ${QWEN_SETTINGS}"
else
    # Deep-merge: keep existing settings, add/merge hooks
    # Custom jq merge: existing hooks + new hooks, existing keys preserved
    tmp_file="$(mktemp)"
    trap "rm -f '$tmp_file'" EXIT

    jq --argjson newcfg "$(cat "$CONFIG_FILE")" '
      def deep_merge($a; $b):
        if ($a | type) == "object" and ($b | type) == "object" then
          $a | to_entries | map(
            if ($b[.key] | type) == "object" then
              {key: .key, value: deep_merge(.value; $b[.key])}
            else
              {key: .key, value: ($b[.key] // .value)}
            end
          ) | from_entries
        else
          ($b // $a)
        end;

      deep_merge(.; $newcfg)
    ' "$QWEN_SETTINGS" > "$tmp_file"

    mv "$tmp_file" "$QWEN_SETTINGS"
    log_info "merged hooks into ${QWEN_SETTINGS}"
fi

# ============================================================================
# COPY agents/, commands/, skills/ TO ~/.qwen/
# ============================================================================

echo ""
echo "Copying agents/, commands/, skills/ to ~/.qwen/..."

for dir in agents commands skills; do
    if [ -d "${PLUGIN_DIR}/${dir}" ]; then
        rm -rf "${HOME}/.qwen/${dir}"
        cp -r "${PLUGIN_DIR}/${dir}" "${HOME}/.qwen/${dir}"
        count=$(find "${HOME}/.qwen/${dir}" -name '*.md' | wc -l | tr -d ' ')
        log_info "  ${dir}/ — ${count} files"
    fi
done

# ============================================================================
# CREATE SENTINEL
# ============================================================================

echo ""
echo "Creating sentinel..."
date > "$SENTINEL"
log_info "created ${SENTINEL}"

# ============================================================================
# INITIALIZE STATE (v6.2 — file-based)
# ============================================================================

echo ""
echo "Initializing state..."
bash "${PLUGIN_DIR}/scripts/state-init.sh"

# ============================================================================
# DONE
# ============================================================================

echo ""
echo "Installation complete!"
echo ""
echo "  Hooks:    ${QWEN_SETTINGS}"
echo "  Agents:   ${HOME}/.qwen/agents/    ($(find "${HOME}/.qwen/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ') files)"
echo "  Commands: ${HOME}/.qwen/commands/   ($(find "${HOME}/.qwen/commands" -name '*.md' 2>/dev/null | wc -l | tr -d ' ') files)"
echo "  Skills:   ${HOME}/.qwen/skills/     ($(find "${HOME}/.qwen/skills" -name '*.md' 2>/dev/null | wc -l | tr -d ' ') files)"
echo ""
echo "Next steps:"
echo "  1. Restart Qwen Code to load the extension"
echo "  2. Verify: /skills (should show devteam skills)"
echo "  3. Verify: /agents manage (should show subagents)"
echo "  4. Verify: /devteam:status"
echo "  5. (Optional) Set GITHUB_TOKEN for GitHub MCP integration"
