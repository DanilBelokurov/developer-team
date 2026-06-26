#!/bin/bash
# DevTeam Qwen Code extension uninstaller.
# Removes DevTeam from the target .qwen/ directory.
# Supports project-level (via project-path argument) and user-level (default) uninstall.
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
# USAGE
# ============================================================================

usage() {
    cat <<EOF
Usage: bash uninstall.sh [project-path]

Uninstalls DevTeam from the target .qwen/ directory.

Arguments:
  project-path    Optional path to a project. If provided, uninstalls from
                  <project-path>/.qwen/. If omitted, auto-detects:
                  - inside git repo: <cwd>/.qwen/
                  - outside git repo: ~/.qwen/

Examples:
  bash uninstall.sh                        # user-level uninstall
  bash uninstall.sh /path/to/myproject    # project-level uninstall
EOF
}

# ============================================================================
# RESOLVE TARGET DIRECTORY
# ============================================================================

resolve_target() {
    local arg_path="$1"

    if [ -n "$arg_path" ]; then
        echo "$(realpath "$arg_path")/.qwen"
        return
    fi

    if git -C . rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "$(pwd)/.qwen"
        return
    fi

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

# ============================================================================
# IDEMPOTENCY CHECK
# ============================================================================

if [ ! -f "$SENTINEL" ]; then
    log_error "not installed at ${TARGET} — nothing to do"
    log_info "Run 'bash install.sh${PROJECT_PATH:+ $PROJECT_PATH}' to install first"
    exit 1
fi

log_info "target: ${TARGET}"

# ============================================================================
# RESOLVE DEVTEAM_DIR (must match install.sh logic)
# ============================================================================
# For project-level install, .devteam/ lives NEXT TO .qwen/ as a sibling —
# i.e. <PROJECT>/.devteam, NOT <PROJECT>/.qwen/.devteam.
# For user-level install, .devteam/ lives INSIDE .qwen/ as ~/.qwen/.devteam.
# install.sh encodes this same rule; we mirror it here so uninstall removes
# what install created.

if [ -n "$PROJECT_PATH" ]; then
    # Project-level: sibling layout. Realpath the user-supplied project path
    # so symlinks are resolved consistently with install.sh.
    DEVTEAM_TARGET="$(realpath "$PROJECT_PATH")/.devteam"
else
    # User-level: nested layout.
    DEVTEAM_TARGET="${TARGET}/.devteam"
fi

# ============================================================================
# REMOVE SENTINEL
# ============================================================================

echo ""
echo "Removing sentinel..."
rm -f "$SENTINEL"
log_info "removed ${SENTINEL}"

# ============================================================================
# REMOVE agents/, commands/, skills/
# ============================================================================

echo ""
echo "Removing DevTeam files..."
for dir in agents commands skills; do
    if [ -d "${TARGET}/${dir}" ]; then
        rm -rf "${TARGET}/${dir}"
        log_info "  removed ${TARGET}/${dir}/"
    fi
done

# ============================================================================
# REMOVE .devteam/ (hooks, scripts, configs, state, mcp-servers/)
# ============================================================================

if [ -d "${DEVTEAM_TARGET}" ]; then
    rm -rf "${DEVTEAM_TARGET}"
    log_info "  removed ${DEVTEAM_TARGET}/"
else
    log_warn "  ${DEVTEAM_TARGET}/ not found — skipping"
fi

# ============================================================================
# REMOVE devteam HOOKS FROM settings.json
# ============================================================================

if [ -f "${TARGET}/settings.json" ]; then
    echo ""
    echo "Cleaning hooks from ${TARGET}/settings.json..."
    tmp_file="$(mktemp)"
    trap "rm -f '$tmp_file'" EXIT

    # Remove hooks key from settings.json
    jq 'delpaths([["hooks"]]) // .' "${TARGET}/settings.json" > "$tmp_file" 2>/dev/null || cp "${TARGET}/settings.json" "$tmp_file"

    # If result is empty object, remove settings.json entirely
    if [ "$(cat "$tmp_file" | tr -d ' \n')" = "{}" ]; then
        rm -f "${TARGET}/settings.json"
        log_info "removed empty ${TARGET}/settings.json"
    else
        mv "$tmp_file" "${TARGET}/settings.json"
        log_info "cleaned hooks from ${TARGET}/settings.json"
    fi
fi

# ============================================================================
# DONE
# ============================================================================

echo ""
log_info "Uninstall complete!"
echo "  Target:   ${TARGET}"
echo "  Sentinel: removed"
echo "  Files:   removed"
echo "  State:   removed"

# ============================================================================
# POST-UNINSTALL NOTES
# ============================================================================

if [ -n "$PROJECT_PATH" ]; then
    # Project-level: everything was inside <PROJECT>/.devteam/ — already gone.
    :
else
    # User-level: ~/mcp-servers/ lives outside ~/.qwen/ and is shared across
    # projects, so we don't auto-remove it. Tell the user.
    if [ -d "${HOME}/mcp-servers" ]; then
        echo ""
        log_warn "Note: ${HOME}/mcp-servers/ was NOT removed (shared across projects)"
        log_warn "  To remove graphfocus venv and related artifacts:"
        log_warn "    rm -rf ${HOME}/mcp-servers"
    fi
fi
