#!/bin/bash
# DevTeam GraphFocus Auto-Index Hook
# Ensures graphfocus index is up-to-date before graph queries
#
# Exit codes:
#   0 = Continue (index is fresh or successfully updated)
#   0 = Skip (graphfocus not installed or disabled)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
if [[ -f "$SCRIPT_DIR/lib/hook-common.sh" ]]; then
    source "$SCRIPT_DIR/lib/hook-common.sh"
elif [[ -f "$SCRIPT_DIR/../lib/hook-common.sh" ]]; then
    source "$SCRIPT_DIR/../lib/hook-common.sh"
fi

init_hook "graphfocus-hook" 2>/dev/null || true

# Check if graphfocus is installed
if ! command -v graphfocus &>/dev/null; then
    log_info "graphfocus-hook" "graphfocus not found, skipping index check" 2>/dev/null || true
    exit 0
fi

# GraphFocus output directory
GRAPH_DIR="${QWEN_CWD:-.}"/graphfocus-out
INDEX_AGE_HOURS=24

# Helper to get index age in hours
get_index_age_hours() {
    if [[ ! -d "$GRAPH_DIR" ]]; then
        echo "999"
        return
    fi
    local cache_file="$GRAPH_DIR/.cache.db"
    if [[ ! -f "$cache_file" ]]; then
        echo "999"
        return
    fi
    local now age_seconds
    now=$(date +%s)
    age_seconds=$(stat -f "%m" "$cache_file" 2>/dev/null || stat -c "%Y" "$cache_file" 2>/dev/null || echo "$now")
    echo $(( (now - age_seconds) / 3600 ))
}

# Check if reindex is needed
should_reindex() {
    if [[ ! -d "$GRAPH_DIR" ]]; then
        return 0  # No graph, need to create
    fi
    local age
    age=$(get_index_age_hours)
    if [[ "$age" -ge "$INDEX_AGE_HOURS" ]]; then
        return 0  # Index is stale
    fi
    return 1  # Index is fresh
}

# Run analysis
run_analysis() {
    log_info "graphfocus-hook" "Analyzing codebase with graphfocus..." 2>/dev/null || true
    if graphfocus analyze . --update 2>&1; then
        log_info "graphfocus-hook" "GraphFocus index updated successfully" 2>/dev/null || true
    else
        log_warn "graphfocus-hook" "GraphFocus analysis failed, continuing with existing index" 2>/dev/null || true
    fi
}

# Main logic
if should_reindex; then
    run_analysis
fi

exit 0
