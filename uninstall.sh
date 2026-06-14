#!/bin/bash
# DevTeam Qwen Code extension uninstaller.
# Removes hooks from ~/.qwen/settings.json and agents/commands/skills from ~/.qwen/.
# Does NOT remove the extension files themselves — use 'qwen extensions uninstall devteam' for that.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
QWEN_SETTINGS="${HOME}/.qwen/settings.json"
SENTINEL="${HOME}/.qwen/.devteam-installed"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[devteam]${NC} $1"; }
log_error() { echo -e "${RED}[devteam]${NC} $1" >&2; }

echo ""

# ============================================================================
# PREREQUISITES
# ============================================================================

command -v jq >/dev/null 2>&1 || {
    log_error "jq is required but not found"
    exit 1
}

# ============================================================================
# REMOVE HOOKS FROM settings.json
# ============================================================================

if [ -f "$QWEN_SETTINGS" ]; then
    if jq -e '.hooks' "$QWEN_SETTINGS" >/dev/null 2>&1; then
        echo "Removing hooks from ${QWEN_SETTINGS}..."
        tmp_file="$(mktemp)"
        trap "rm -f '$tmp_file'" EXIT

        jq 'del(.hooks)' "$QWEN_SETTINGS" > "$tmp_file"
        mv "$tmp_file" "$QWEN_SETTINGS"
        log_info "removed hooks from ${QWEN_SETTINGS}"
    else
        echo "No hooks found in ${QWEN_SETTINGS} — skipping"
    fi
else
    echo "settings.json not found — skipping hooks removal"
fi

# ============================================================================
# REMOVE agents/, commands/, skills/ FROM ~/.qwen/
# ============================================================================

echo ""
echo "Removing agents/, commands/, skills/ from ~/.qwen/..."

for dir in agents commands skills; do
    if [ -d "${HOME}/.qwen/${dir}" ]; then
        rm -rf "${HOME}/.qwen/${dir}"
        log_info "removed ${HOME}/.qwen/${dir}/"
    fi
done

# ============================================================================
# REMOVE SENTINEL
# ============================================================================

if [ -f "$SENTINEL" ]; then
    rm -f "$SENTINEL"
    log_info "removed ${SENTINEL}"
fi

# ============================================================================
# DONE
# ============================================================================

echo ""
echo "Uninstall complete!"
echo ""
echo "Note: extension files at the install path were NOT removed."
echo "Run 'qwen extensions uninstall devteam' to fully remove the extension."
echo "Run 'qwen extensions disable devteam' to keep files but stop loading."
