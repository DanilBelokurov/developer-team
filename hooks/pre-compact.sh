#!/bin/bash
# DevTeam Pre-Compact Hook
# Saves critical state before context compaction to preserve important information

set -euo pipefail

# Configuration
MEMORY_DIR=".devteam/memory"
COMPACT_FILE="$MEMORY_DIR/pre-compact-$(date +%Y%m%d-%H%M%S).md"

# Source common library for SQLite helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/lib/hook-common.sh" ]]; then
    source "$SCRIPT_DIR/lib/hook-common.sh"
elif [[ -f "$SCRIPT_DIR/../lib/hook-common.sh" ]]; then
    source "$SCRIPT_DIR/../lib/hook-common.sh"
else
    echo "[DevTeam Pre-Compact] Warning: hook-common.sh not found" >&2
    exit 0
fi

# Logging function
log() {
    echo "[DevTeam Pre-Compact] $1"
}

# ============================================
# SAVE CRITICAL CONTEXT
# ============================================
save_critical_context() {
    mkdir -p "$MEMORY_DIR"

    cat > "$COMPACT_FILE" << 'HEADER'
# Pre-Compaction State Snapshot

This file was created automatically before context compaction.
It preserves critical information that should not be lost.

HEADER

    # Add current task context from file-based state (no SQLite)
    echo "## Current Execution State" >> "$COMPACT_FILE"
    echo "" >> "$COMPACT_FILE"

    local db_sprint db_task db_phase
    db_sprint=$(get_kv_state active_sprint "" 2>/dev/null || echo "")
    [[ -z "$db_sprint" ]] && db_sprint="none"
    db_task=$(get_current_task 2>/dev/null || echo "")
    [[ -z "$db_task" ]] && db_task="none"
    db_phase=$(get_current_phase 2>/dev/null || echo "")
    [[ -z "$db_phase" ]] && db_phase="unknown"

    echo "- Sprint: ${db_sprint:-none}" >> "$COMPACT_FILE"
    echo "- Task: ${db_task:-none}" >> "$COMPACT_FILE"
    echo "- Phase: ${db_phase:-unknown}" >> "$COMPACT_FILE"

    # If there's an active task, look up its status from the task markdown.
    CURRENT_TASK="${db_task:-}"
    if [ -n "$CURRENT_TASK" ] && [ "$CURRENT_TASK" != "none" ]; then
        local task_file=".devteam/state/tasks/${CURRENT_TASK}.md"
        if [[ -f "$task_file" ]]; then
            local task_status task_iteration task_tier
            task_status=$(get_frontmatter_value "$task_file" "status")
            task_iteration=$(get_frontmatter_value "$task_file" "iteration")
            task_tier=$(get_frontmatter_value "$task_file" "tier")

            echo "" >> "$COMPACT_FILE"
            echo "### Current Task Details" >> "$COMPACT_FILE"
            echo "" >> "$COMPACT_FILE"
            echo "- Status: ${task_status:-unknown}" >> "$COMPACT_FILE"
            echo "- Iteration: ${task_iteration:-0}" >> "$COMPACT_FILE"
            echo "- Complexity Tier: ${task_tier:-unknown}" >> "$COMPACT_FILE"
        fi
    fi

    echo "" >> "$COMPACT_FILE"

    # Add autonomous mode status
    if [ -f ".devteam/autonomous-mode" ]; then
        echo "## Autonomous Mode" >> "$COMPACT_FILE"
        echo "" >> "$COMPACT_FILE"
        echo "Autonomous mode is ACTIVE. Continue working until EXIT_SIGNAL." >> "$COMPACT_FILE"
        echo "" >> "$COMPACT_FILE"

        if [ -f ".devteam/circuit-breaker.json" ]; then
            echo "### Circuit Breaker Status" >> "$COMPACT_FILE"
            echo '```json' >> "$COMPACT_FILE"
            cat ".devteam/circuit-breaker.json" >> "$COMPACT_FILE"
            echo '```' >> "$COMPACT_FILE"
            echo "" >> "$COMPACT_FILE"
        fi
    fi

    # Add reminder about state file
    cat >> "$COMPACT_FILE" << 'FOOTER'

## Important Reminders

1. Full state is in `.devteam/state/` (file-based) - read session/task markdown to understand progress
2. Check task status before starting work
3. Update state after completing tasks
4. Output `EXIT_SIGNAL: true` only when ALL work is genuinely complete

## Recovery Instructions

If resuming after compaction:
1. Read `.devteam/state/sessions/<id>.md` to understand current state
2. Continue from the current task/sprint
3. Do not restart completed work

FOOTER

    log "Critical context saved to $COMPACT_FILE"
}

# ============================================
# OUTPUT CONTEXT FOR QWEN
# ============================================
output_context() {
    # This output will be preserved in Claude's context after compaction
    echo ""
    echo "## Post-Compaction Context"
    echo ""

    if [ -f "$COMPACT_FILE" ]; then
        cat "$COMPACT_FILE"
    fi
}

# ============================================
# MAIN EXECUTION
# ============================================
main() {
    log "Preparing for context compaction..."

    # Save critical context
    save_critical_context

    # Output for Claude
    output_context

    log "Pre-compact preparation complete"
}

# Run main function
main
