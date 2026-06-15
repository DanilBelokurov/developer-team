#!/bin/bash
# DevTeam Qwen Code extension installer.
# Installs via 'qwen extensions install .' (hooks/settings in qwen-extension.json)
# This script: prerequisites check + state initialization only.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"

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
echo "Next steps:"
echo "  1. qwen extensions install ."
echo "  2. Restart Qwen Code to load the extension"
echo "  3. Verify: /devteam:status"
