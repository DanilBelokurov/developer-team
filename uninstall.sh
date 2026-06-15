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
# REMOVE SENTINEL
# ============================================================================

echo ""
echo "Removing sentinel..."
rm -f "$SENTINEL"
log_info "removed ${SENTINEL}"

# ============================================================================
# REMOVE agents/, commands/, skills/, hooks/
# ============================================================================

echo ""
echo "Removing DevTeam files..."
for dir in agents commands skills hooks; do
    if [ -d "${TARGET}/${dir}" ]; then
        rm -rf "${TARGET}/${dir}"
        log_info "  removed ${TARGET}/${dir}/"
    fi
done

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
# REMOVE .devteam/ STATE
# ============================================================================

# Project-level: .devteam/ is sibling to .qwen/ at project root
# User-level: .devteam/ is inside .qwen/
if [ -n "$PROJECT_PATH" ]; then
    DEVTEAM_STATE="${PROJECT_PATH}/.devteam"
else
    DEVTEAM_STATE="${TARGET}/.devteam"
fi
if [ -d "$DEVTEAM_STATE" ]; then
    echo ""
    echo "Removing DevTeam state..."
    rm -rf "$DEVTEAM_STATE"
    log_info "removed ${DEVTEAM_STATE}/"
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
