#!/bin/bash
# DevTeam GraphFocus Auto-Index Hook
# Ensures graphfocus index is up-to-date before graph queries
#
# Exit codes:
#   0 = Continue (index is fresh or successfully updated)
#   0 = Skip (graphfocus not installed or disabled)
#
# Configuration via environment variables:
#   GRAPHFOCUS_PYTHON   - Python interpreter (default: python3)
#   GRAPHFOCUS_SCRIPT   - Path to graphfocus script (default: graphfocus)
#   GRAPHFOCUS_TIMEOUT  - Timeout for analysis in seconds (default: 300)
#   GRAPH_DIR           - Output directory (default: ./graphfocus-out)
#   INDEX_AGE_HOURS     - Staleness threshold in hours (default: 24)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
if [[ -f "$SCRIPT_DIR/lib/hook-common.sh" ]]; then
    source "$SCRIPT_DIR/lib/hook-common.sh"
elif [[ -f "$SCRIPT_DIR/../lib/hook-common.sh" ]]; then
    source "$SCRIPT_DIR/../lib/hook-common.sh"
fi

init_hook "graphfocus-hook" 2>/dev/null || true

# ============================================================================
# CONFIGURATION
# ============================================================================

# GraphFocus paths (customizable via environment)
GRAPHFOCUS_PYTHON="${GRAPHFOCUS_PYTHON:-python3}"
GRAPHFOCUS_SCRIPT="${GRAPHFOCUS_SCRIPT:-graphfocus}"
GRAPHFOCUS_TIMEOUT="${GRAPHFOCUS_TIMEOUT:-300}"

# Index configuration
GRAPH_DIR="${QWEN_CWD:-.}"/graphfocus-out
INDEX_AGE_HOURS="${INDEX_AGE_HOURS:-24}"

# ============================================================================
# GRAPHFOCUS EXECUTION
# ============================================================================

# Build the full command based on configuration
build_graphfocus_cmd() {
    local subcommand="$1"
    shift
    local args="$@"

    # If GRAPHFOCUS_SCRIPT is an absolute path with .py extension, use python
    if [[ "$GRAPHFOCUS_SCRIPT" == *.py ]]; then
        echo "$GRAPHFOCUS_PYTHON" "$GRAPHFOCUS_SCRIPT" "$subcommand" $args
    # If GRAPHFOCUS_SCRIPT contains a path separator, might need python
    elif [[ "$GRAPHFOCUS_SCRIPT" == */* ]]; then
        echo "$GRAPHFOCUS_PYTHON" "$GRAPHFOCUS_SCRIPT" "$subcommand" $args
    else
        # Standard command in PATH
        echo "$GRAPHFOCUS_SCRIPT" "$subcommand" $args
    fi
}

# Check if graphfocus is available
check_graphfocus_installed() {
    local cmd
    cmd=$(build_graphfocus_cmd "" 2>/dev/null || true)

    if [[ "$cmd" == *"/"* ]]; then
        # Has path separator - check if file exists
        local script_path
        script_path=$(echo "$cmd" | awk '{print $2}')
        [[ -f "$script_path" ]]
    elif command -v "$GRAPHFOCUS_SCRIPT" &>/dev/null; then
        true
    else
        false
    fi
}

# ============================================================================
# INDEX AGE CHECKING
# ============================================================================

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

# ============================================================================
# ANALYSIS
# ============================================================================

run_analysis() {
    log_info "graphfocus-hook" "Analyzing codebase with graphfocus..." 2>/dev/null || true

    local cmd
    cmd=$(build_graphfocus_cmd "analyze" "." "--update" "--ai")

    if timeout "$GRAPHFOCUS_TIMEOUT" bash -c "$cmd" 2>&1; then
        log_info "graphfocus-hook" "GraphFocus index updated successfully" 2>/dev/null || true
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_warn "graphfocus-hook" "GraphFocus analysis timed out after ${GRAPHFOCUS_TIMEOUT}s" 2>/dev/null || true
        else
            log_warn "graphfocus-hook" "GraphFocus analysis failed (exit $exit_code), continuing with existing index" 2>/dev/null || true
        fi
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # Check if graphfocus is available
    if ! check_graphfocus_installed; then
        log_info "graphfocus-hook" "graphfocus not found (GRAPHFOCUS_SCRIPT=${GRAPHFOCUS_SCRIPT}), skipping index check" 2>/dev/null || true
        exit 0
    fi

    # Check if reindex is needed
    if should_reindex; then
        run_analysis
    fi

    exit 0
}

main "$@"
