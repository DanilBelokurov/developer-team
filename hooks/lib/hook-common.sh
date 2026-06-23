#!/bin/bash
# Hook-Common Library
# Bridge between hook scripts and DevTeam infrastructure (state.sh, events.sh)
# All hook scripts source this file for a stable API layer.
#
# v6.3 — file-based storage (no SQLite dependency)

# Resolve plugin root from this file's location (hooks/lib/ -> project root)
HOOK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HOOK_LIB_DIR/../.." && pwd)"

# Source infrastructure (graceful degradation if missing)
source "${PLUGIN_ROOT}/scripts/state.sh" 2>/dev/null || true
source "${PLUGIN_ROOT}/scripts/events.sh" 2>/dev/null || true
source "${PLUGIN_ROOT}/scripts/lib/common.sh" 2>/dev/null || true

# ============================================================================
# CONFIGURATION DEFAULTS
# ============================================================================

DEVTEAM_DIR="${DEVTEAM_DIR:-.devteam}"
STATE_DIR="${STATE_DIR:-${DEVTEAM_DIR}/state}"
AUTONOMOUS_MARKER="${DEVTEAM_DIR}/autonomous-mode"

# ============================================================================
# LOGGING (fallback implementations if not available from infra)
# ============================================================================

if ! declare -f log_debug &>/dev/null 2>/dev/null; then
    log_debug() { echo "[debug] [$1] $2" >&2; }
fi
if ! declare -f log_info &>/dev/null 2>/dev/null; then
    log_info()  { echo "[info]  [$1] $2" >&2; }
fi
if ! declare -f log_warn &>/dev/null 2>/dev/null; then
    log_warn()  { echo "[warn]  [$1] $2" >&2; }
fi
if ! declare -f log_error &>/dev/null 2>/dev/null; then
    log_error() { echo "[error] [$1] $2" >&2; }
fi

# ============================================================================
# HOOK LOGGING (observability for hook invocations)
# ============================================================================

# HOOK_VERBOSE - set to "true" to enable detailed hook logging
HOOK_VERBOSE="${HOOK_VERBOSE:-false}"

# log_hook_invocation - Logs hook invocation with parameters to file
# Usage: log_hook_invocation "hook_name" "tool_name" "input_summary" "duration_ms"
log_hook_invocation() {
    local hook_name="${1:-unknown}"
    local tool_name="${2:-}"
    local input_summary="${3:-}"
    local duration_ms="${4:-0}"
    local exit_code="${5:-0}"

    local log_file="${DEVTEAM_DIR}/logs/hooks-$(date +%Y-%m-%d).jsonl"
    mkdir -p "$(dirname "$log_file")"

    # Get current context
    local context
    context=$(get_hook_context 2>/dev/null || echo '{}')

    # Build JSON log entry
    local log_entry
    log_entry=$(printf '%s' "$context" | python3 -c "
import json, sys, datetime
try:
    ctx = json.load(sys.stdin)
    entry = {
        'ts': datetime.datetime.utcnow().isoformat() + 'Z',
        'hook': '$hook_name',
        'tool': '$tool_name',
        'input_summary': '$input_summary',
        'duration_ms': $duration_ms,
        'exit_code': $exit_code,
        'session': ctx.get('session', ''),
        'task': ctx.get('task', ''),
        'iteration': ctx.get('iteration', 0),
        'failures': ctx.get('failures', 0)
    }
    print(json.dumps(entry))
except:
    print(json.dumps({'ts': datetime.datetime.utcnow().isoformat() + 'Z', 'hook': '$hook_name'}))
" 2>/dev/null || echo "{}")

    echo "$log_entry" >> "$log_file"

    # Also log to stderr if verbose mode is enabled
    if [[ "${HOOK_VERBOSE}" == "true" ]]; then
        log_debug "$hook_name" "Invoked: tool=$tool_name, exit=$exit_code, duration=${duration_ms}ms"
    fi
}

# log_hook_event - Logs a specific hook event with data
# Usage: log_hook_event "event_type" "data_json"
log_hook_event() {
    local event_type="${1:-hook_event}"
    local data="${2:-{}}"

    log_event_to_db "hook_$event_type" "hook" "Hook event: $event_type" "$data"
}

# ============================================================================
# HOOK INITIALIZATION
# ============================================================================

init_hook() {
    local hook_name="${1:-unknown}"
    export CURRENT_HOOK="$hook_name"

    # Ensure runtime directories exist
    if declare -f ensure_state_dir &>/dev/null 2>/dev/null; then
        ensure_state_dir
    else
        mkdir -p "${DEVTEAM_DIR}/state" 2>/dev/null || true
    fi
}

# ============================================================================
# SESSION & STATE ACCESSORS
# These delegate to state.sh functions. The functions are sourced directly,
# no wrapper layer needed — state.sh provides graceful degradation internally.
# ============================================================================

# get_current_session_id() — from state.sh
# get_current_task() — from state.sh (via get_state)
# get_current_iteration() — from state.sh
# get_consecutive_failures() — from state.sh
# get_current_model() — from state.sh
# increment_failures() — from state.sh
# reset_failures() — from state.sh
# set_phase() — from state.sh
# set_current_agent() — from state.sh
# set_current_model() — from state.sh

# Convenience wrappers for backward compatibility
get_current_session() {
    if declare -f get_current_session_id &>/dev/null 2>/dev/null; then
        get_current_session_id
    else
        echo ""
    fi
}

get_current_task() {
    if declare -f get_state &>/dev/null 2>/dev/null; then
        get_state "current_task_id" ""
    else
        echo ""
    fi
}

# ============================================================================
# CONTEXT INJECTION
# ============================================================================

inject_system_message() {
    local id="$1"
    local message="$2"

    # Escape message for JSON
    local escaped_msg
    escaped_msg=$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')

    # Output JSON context injection to stdout (Qwen Code hook protocol)
    cat <<EOF
{"id":"devteam-${id}","type":"system","message":"${escaped_msg}"}
EOF
}

# ============================================================================
# SCOPE CHECKING
# ============================================================================

file_in_scope() {
    local file_path="$1"

    # If no scope is defined, all files are in scope
    local scope_file="${DEVTEAM_DIR}/task-scope.txt"
    if [[ ! -f "$scope_file" ]]; then
        return 0
    fi

    # Normalize the file path
    local normalized
    normalized=$(realpath -m "$file_path" 2>/dev/null || echo "$file_path")

    # Check against scope definitions
    while IFS= read -r scope_pattern; do
        # Skip empty lines and comments
        [[ -z "$scope_pattern" ]] && continue
        [[ "$scope_pattern" == \#* ]] && continue

        # Check if file matches the pattern
        if [[ "$file_path" == $scope_pattern ]] || [[ "$normalized" == *"$scope_pattern"* ]]; then
            return 0
        fi
    done < "$scope_file"

    return 1
}

get_scope_files() {
    local scope_file="${DEVTEAM_DIR}/task-scope.txt"
    if [[ -f "$scope_file" ]]; then
        grep -v '^#' "$scope_file" | grep -v '^$'
    else
        echo "(no scope defined - all files allowed)"
    fi
}

# ============================================================================
# EVENT LOGGING (delegated to events.sh)
# ============================================================================

log_event_to_db() {
    local event_type="$1"
    local category="$2"
    local message="$3"
    local data="${4:-"{}"}"

    # Delegate to events.sh log_event if available
    if declare -f log_event &>/dev/null 2>/dev/null; then
        log_event "$event_type" "$category" "$message" "$data" 2>/dev/null || true
        return
    fi

    # Fallback: append to events file directly
    local today
    today=$(date +%Y-%m-%d)
    local events_file="${STATE_DIR}/events/${today}-events.md"

    mkdir -p "${STATE_DIR}/events"
    if [[ -f "$events_file" ]]; then
        local now
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        printf '## %s — %s\n- category: %s\n- message: %s\n- data: %s\n\n' \
            "$now" "$event_type" "$category" "$message" "$data" >> "$events_file"
    fi
}

# ============================================================================
# MCP NOTIFICATION
# ============================================================================

mcp_notify() {
    local event="$1"
    local data="${2:-"{}"}"

    # Best-effort notification via unix socket
    local sock="${DEVTEAM_DIR}/mcp.sock"
    if [[ -S "$sock" ]]; then
        local safe_event="${event//\"/\\\"}"
        printf '{"event":"%s","data":%s}\n' "$safe_event" "$data" | socat - UNIX-CONNECT:"$sock" 2>/dev/null || true
    fi
    # Silently no-op if socket unavailable
}

# ============================================================================
# HOOK CONTEXT
# ============================================================================

# get_hook_context - Returns JSON with current hook/session context for logging
get_hook_context() {
    local session_id=""
    local task_id=""
    local iteration="0"
    local failures="0"
    local model="sonnet"

    # Get values from state.sh functions if available
    if declare -f get_current_session_id &>/dev/null 2>/dev/null; then
        session_id=$(get_current_session_id 2>/dev/null || echo "")
    fi
    if declare -f get_state &>/dev/null 2>/dev/null; then
        task_id=$(get_state "current_task_id" "" 2>/dev/null || echo "")
    fi
    if declare -f get_current_iteration &>/dev/null 2>/dev/null; then
        iteration=$(get_current_iteration 2>/dev/null || echo "0")
    fi
    if declare -f get_consecutive_failures &>/dev/null 2>/dev/null; then
        failures=$(get_consecutive_failures 2>/dev/null || echo "0")
    fi
    if declare -f get_current_model &>/dev/null 2>/dev/null; then
        model=$(get_current_model 2>/dev/null || echo "sonnet")
    fi

    # JSON-escape values
    local safe_session="${session_id//\"/\\\"}"
    local safe_task="${task_id//\"/\\\"}"

    cat <<EOF
{"session":"${safe_session:-}","task":"${safe_task:-}","iteration":${iteration:-0},"failures":${failures:-0},"model":"${model:-sonnet}","hook":"${CURRENT_HOOK:-unknown}"}
EOF
}


# ============================================================================
# ESCALATION
# ============================================================================

trigger_escalation() {
    local reason="$1"

    log_warn "${CURRENT_HOOK:-hook}" "Escalation triggered: $reason"

    # Log to events
    log_event_to_db "model_escalated" "escalation" "Escalation: $reason" "{\"reason\":\"${reason//\"/\\\"}\"}"

    # Record escalation in state.sh if available
    if declare -f record_escalation &>/dev/null 2>/dev/null; then
        record_escalation "$reason" 2>/dev/null || true
    fi
}

# ============================================================================
# AUTONOMOUS MODE & CIRCUIT BREAKER
# ============================================================================

is_autonomous_mode() {
    [[ -f "$AUTONOMOUS_MARKER" ]]
}

is_circuit_breaker_open() {
    if declare -f should_trip_circuit_breaker &>/dev/null 2>/dev/null; then
        should_trip_circuit_breaker
    else
        local failures="0"
        if declare -f get_consecutive_failures &>/dev/null 2>/dev/null; then
            failures=$(get_consecutive_failures 2>/dev/null || echo "0")
        fi
        if ! [[ "$failures" =~ ^[0-9]+$ ]]; then failures=0; fi
        [[ "$failures" -ge 5 ]]
    fi
}

is_max_iterations_reached() {
    if declare -f is_max_iterations_reached &>/dev/null 2>/dev/null; then
        is_max_iterations_reached
    else
        local iteration="0"
        if declare -f get_current_iteration &>/dev/null 2>/dev/null; then
            iteration=$(get_current_iteration 2>/dev/null || echo "0")
        fi
        if ! [[ "$iteration" =~ ^[0-9]+$ ]]; then iteration=0; fi
        [[ "$iteration" -ge 100 ]]
    fi
}

# ============================================================================
# CHECKPOINTS
# ============================================================================

save_checkpoint() {
    local message="${1:-Auto-checkpoint}"

    # Delegate to state.sh if available
    if declare -f save_checkpoint &>/dev/null 2>/dev/null; then
        save_checkpoint "$message"
        return
    fi

    # Fallback: create checkpoint file
    local session_id=""
    if declare -f get_current_session_id &>/dev/null 2>/dev/null; then
        session_id=$(get_current_session_id 2>/dev/null || echo "")
    fi
    [[ -z "$session_id" ]] && return

    local checkpoint_dir="${STATE_DIR}/checkpoints"
    mkdir -p "$checkpoint_dir"

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '# Checkpoint\nsession_id: %s\ntimestamp: %s\nmessage: %s\n' \
        "$session_id" "$now" "$message" > "${checkpoint_dir}/${now}.md"
}

# ============================================================================
# DATABASE HELPERS (legacy compatibility — file-based storage)
# ============================================================================

db_exists() {
    # File-based storage doesn't use a single DB file
    # Return true if state directory exists
    [[ -d "$STATE_DIR" ]]
}

db_query() {
    # Not applicable for file-based storage
    echo ""
}
