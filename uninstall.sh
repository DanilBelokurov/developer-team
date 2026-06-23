#!/bin/bash
# DevTeam Qwen Code extension uninstaller.
# Removes hooks and state — everything install.sh installed.
#
# What this script removes:
#   - .devteam/hooks/ (lifecycle hooks)
#   - .devteam/state/ (session state)
#   - .devteam-installed (sentinel file)
#   - hooks from settings.json
#
# What this script does NOT remove:
#   - agents/, commands/, skills/ (managed by 'qwen extensions uninstall .')
#
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

Uninstalls DevTeam hooks and state from the target .qwen/ directory.

Note: agents/, commands/, skills/ are managed by 'qwen extensions uninstall .'
      and are NOT removed by this script.

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
# REMOVE .devteam/hooks/ AND .devteam/state/
# ============================================================================

DEVTEAM_TARGET="${TARGET}/.devteam"

echo ""
echo "Removing DevTeam hooks and state..."

# Remove hooks/ (lifecycle hooks installed by install.sh)
if [ -d "${DEVTEAM_TARGET}/hooks" ]; then
    rm -rf "${DEVTEAM_TARGET}/hooks"
    log_info "  removed ${DEVTEAM_TARGET}/hooks/"
fi

# Remove state/ (session state initialized by install.sh)
if [ -d "${DEVTEAM_TARGET}/state" ]; then
    rm -rf "${DEVTEAM_TARGET}/state"
    log_info "  removed ${DEVTEAM_TARGET}/state/"
fi

# Remove .devteam/ entirely if empty (only config might remain)
if [ -d "${DEVTEAM_TARGET}" ]; then
    if [ -z "$(ls -A "${DEVTEAM_TARGET}" 2>/dev/null)" ]; then
        rmdir "${DEVTEAM_TARGET}"
        log_info "  removed empty ${DEVTEAM_TARGET}/"
    fi
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
echo ""
echo "  Target:   ${TARGET}"
echo "  Sentinel: removed"
echo "  Hooks:    removed"
echo "  State:    removed"
echo ""
echo "Note: agents/, commands/, skills/ are managed by 'qwen extensions uninstall .'"
echo "      To fully remove DevTeam, also run:"
echo "        qwen extensions uninstall devteam"
