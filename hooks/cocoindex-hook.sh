#!/bin/bash
# DevTeam CocoIndex Auto-Index Hook
# Runs before cocoindex_search to ensure index is fresh
#
# Exit codes:
#   0 = Continue (index is fresh or successfully updated)
#   0 = Skip (cocoindex not installed or disabled)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
if [[ -f "$SCRIPT_DIR/lib/hook-common.sh" ]]; then
    source "$SCRIPT_DIR/lib/hook-common.sh"
elif [[ -f "$SCRIPT_DIR/../lib/hook-common.sh" ]]; then
    source "$SCRIPT_DIR/../lib/hook-common.sh"
fi

init_hook "cocoindex-hook" 2>/dev/null || true

# Check if cocoindex is installed
if ! command -v ccc &>/dev/null; then
    log_info "cocoindex-hook" "ccc not found, skipping index check" 2>/dev/null || true
    exit 0
fi

# Check if index directory exists
INDEX_DIR="${CLAUDE_CWD:-.}"/.cocoindex
INDEX_AGE_HOURS=24

# Helper to get index age in hours
get_index_age_hours() {
    if [[ ! -d "$INDEX_DIR" ]]; then
        echo "999"
        return
    fi
    local newest_file
    newest_file=$(find "$INDEX_DIR" -type f -name "*.db" 2>/dev/null | head -1)
    if [[ -z "$ newest_file" ]]; then
        echo "999"
        return
    fi
    local now age_seconds
    now=$(date +%s)
    age_seconds=$(stat -f "%m" "$newest_file" 2>/dev/null || stat -c "%Y" "$newest_file" 2>/dev/null || echo "$now")
    echo $(( (now - age_seconds) / 3600 ))
}

# Check if reindex is needed
should_reindex() {
    if [[ ! -d "$INDEX_DIR" ]]; then
        return 0  # No index, need to create
    fi
    local age
    age=$(get_index_age_hours)
    if [[ "$age" -ge "$INDEX_AGE_HOURS" ]]; then
        return 0  # Index is stale
    fi
    return 1  # Index is fresh
}

# Run indexing
run_index() {
    log_info "cocoindex-hook" "Indexing codebase with cocoindex..." 2>/dev/null || true
    if ccc index 2>&1; then
        log_info "cocoindex-hook" "Index updated successfully" 2>/dev/null || true
    else
        log_warn "cocoindex-hook" "Index update failed, continuing with existing index" 2>/dev/null || true
    fi
}

# Main logic
if should_reindex; then
    run_index
fi

exit 0
