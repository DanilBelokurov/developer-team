#!/bin/bash
# DevTeam Stop Hook (v6.5 — file-based)
# Implements session persistence for autonomous mode.
# Prevents the agent from exiting without a proper completion signal.
#
# Exit codes:
#   0 = Allow exit (work complete or not in autonomous mode)
#   2 = Block exit and re-inject prompt (work not complete)
#
# Environment variables expected:
#   STOP_HOOK_MESSAGE or CLAUDE_OUTPUT — last assistant message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/lib/hook-common.sh" ]]; then
    source "$SCRIPT_DIR/lib/hook-common.sh"
elif [[ -f "$SCRIPT_DIR/../lib/hook-common.sh" ]]; then
    source "$SCRIPT_DIR/../lib/hook-common.sh"
else
    echo "[stop] Warning: hook-common.sh not found" >&2
    exit 0
fi

init_hook "stop"
prime_hot_cache

# ============================================================================
# CONFIGURATION
# ============================================================================

MESSAGE="${STOP_HOOK_MESSAGE:-${CLAUDE_OUTPUT:-}}"

# ============================================================================
# VALID EXIT SIGNALS
# ============================================================================

VALID_EXIT_SIGNALS=(
    "EXIT_SIGNAL: true"
    "EXIT_SIGNAL:true"
    "All quality gates passed"
    "Task completed successfully"
    "Implementation complete"
    "Session ended"
    "All tasks completed"
    "Sprint completed"
    "/devteam:end"
)

# ============================================================================
# EXIT SIGNAL DETECTION (H5-style: single combined grep)
# ============================================================================

has_valid_exit_signal() {
    local message="$1"
    # Build one regex with all patterns alternated.
    local combined
    combined=$(printf '%s\n' "${VALID_EXIT_SIGNALS[@]}" | sed 's/[][(){}.*+?^$|\\]/\\&/g' | paste -sd'|' -)
    # -m1: stop at first match (early exit). -qi: case-insensitive.
    grep -m1 -qiE "$combined" <<< "$message"
}

# ============================================================================
# SESSION STATE CHECK (H6 fix)
# ============================================================================
# Previous implementation queried a non-existent SQLite DB for in-progress
# tasks and always returned "no incomplete work", causing autonomous mode
# to exit prematurely. New implementation scans the file-based task store
# at .devteam/state/tasks/*.md frontmatter.

has_incomplete_work() {
    local sid
    sid=$(get_current_session_id 2>/dev/null || echo "")
    if [[ -z "$sid" ]]; then
        return 1  # No session = nothing to do
    fi

    local tasks_dir="${DEVTEAM_DIR}/state/tasks"
    [[ -d "$tasks_dir" ]] || return 1

    # H6 fix: scan task markdown files for status: in_progress / pending
    # in frontmatter. Use awk once instead of multiple grep passes.
    local in_progress
    in_progress=$(awk -F': *' '
        /^---$/ { fm = !fm; next }
        fm && /^status:/ { v = $2; gsub(/[ \r\n]/,"",v); if (v=="in_progress"||v=="pending") print v }
    ' "$tasks_dir"/*.md 2>/dev/null | wc -l | tr -d ' ')

    [[ "${in_progress:-0}" =~ ^[0-9]+$ ]] || in_progress=0
    if [[ "$in_progress" -gt 0 ]]; then
        log_info "stop" "Found $in_progress in-progress/pending tasks"
        return 0
    fi

    # Also check the running session itself for recent failures recorded in
    # the event log of the last 5 minutes.
    local today; today=$(date +%Y-%m-%d)
    local events_file="${DEVTEAM_DIR}/state/events/${today}-events.md"
    if [[ -f "$events_file" ]]; then
        local recent_failures
        recent_failures=$(tail -n 1000 "$events_file" 2>/dev/null \
            | awk -v sid="$sid" '
                /^## / { ts = substr($0, 4, 19); now = strftime("%Y-%m-%dT%H:%M:%S"); recent = 0 }
                /^- session_id: / { if ($0 ~ sid) recent = 1; next }
                recent && /^## .*— (gate_failed|agent_failed|task_failed)/ { print; recent = 0; next }
                recent { recent = 0 }
            ' \
            | grep -c "^## .*— " || echo "0")
        recent_failures="${recent_failures:-0}"
        if [[ "$recent_failures" =~ ^[0-9]+$ ]] && [[ "$recent_failures" -gt 0 ]]; then
            log_info "stop" "Found $recent_failures recent failures in event log"
            return 0
        fi
    fi

    return 1
}

# ============================================================================
# SESSION CLEANUP
# ============================================================================

cleanup_session() {
    local exit_reason="${1:-completed}"
    rm -f "$AUTONOMOUS_MARKER" 2>/dev/null || true

    # Use state.sh's end_session if available.
    if declare -f end_session &>/dev/null; then
        end_session "completed" "$exit_reason" 2>/dev/null || true
    fi

    local safe_reason="${exit_reason//\\/\\\\}"
    safe_reason="${safe_reason//\"/\\\"}"
    safe_reason="${safe_reason//$'\n'/\\n}"
    mcp_notify "session_exit" "{\"authorized\": true, \"reason\": \"$safe_reason\"}"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    if ! is_autonomous_mode; then
        log_debug "stop" "Not in autonomous mode, allowing exit"
        exit 0
    fi

    if [[ -n "$MESSAGE" ]] && has_valid_exit_signal "$MESSAGE"; then
        log_info "stop" "Valid exit signal detected"
        save_exit_checkpoint
        cleanup_session "completed"
        exit 0
    fi

    if is_circuit_breaker_open; then
        log_warn "stop" "Circuit breaker OPEN — allowing exit for human intervention"
        save_exit_checkpoint
        cleanup_session "circuit_breaker"

        inject_system_message "circuit-breaker" "
CIRCUIT BREAKER TRIPPED

Maximum consecutive failures ($MAX_FAILURES) reached.
Human intervention is required.

Session has been paused. Check .devteam/state/ for details.
"
        exit 0
    fi

    if is_max_iterations_reached; then
        log_warn "stop" "Maximum iterations ($MAX_ITERATIONS) reached"
        save_exit_checkpoint
        cleanup_session "max_iterations"

        inject_system_message "max-iterations" "
MAXIMUM ITERATIONS REACHED

The session has reached $MAX_ITERATIONS iterations.
Review progress in .devteam/ and decide next steps.
"
        exit 0
    fi

    # Autonomous mode + no valid exit signal + no circuit breaker + no max
    # iter → BLOCK the exit. This is the core enforcement of autonomous mode.
    log_warn "stop" "Exit blocked — no valid exit signal in autonomous mode"
    log_event_to_db "exit_blocked" "persistence" "Exit blocked — no valid exit signal"

    local session_id; session_id=$(get_current_session)
    local task_id; task_id=$(get_current_task)
    local iteration; iteration=$(get_current_iteration)
    [[ "$iteration" =~ ^[0-9]+$ ]] || iteration=0

    inject_system_message "exit-blocked" "
EXIT BLOCKED

Autonomous mode requires a valid exit signal.

Current state:
- Session: ${session_id:-none}
- Task: ${task_id:-none}
- Iteration: ${iteration:-0}/$MAX_ITERATIONS

You must either:
1. Complete the task (all quality gates pass)
2. Save progress with a checkpoint
3. Use devteam_end_session with appropriate status

Include EXIT_SIGNAL: true when properly complete.
"

    # H2 fix: increment via state.sh (which writes to the markdown frontmatter
    # that is_max_iterations_reached actually reads). The previous SQLite
    # UPDATE was a dead write.
    if declare -f increment_iteration &>/dev/null; then
        increment_iteration 2>/dev/null || true
    fi

    # Refresh cache so next hook event sees the new iteration count.
    prime_hot_cache

    mcp_notify "exit_blocked" "$(get_claude_context)"

    exit 2
}

main "$@"