#!/bin/bash
# Hook-Common Library (v6.5 — file-based, no SQLite)
# Bridge between hook scripts and DevTeam infrastructure.
#
# All hook scripts source this file for a stable API layer. State is read
# exclusively from .devteam/state/ via scripts/state.sh — there is no
# SQLite dependency. SQLite-style helpers (db_query, db_exists) are kept
# as no-op stubs so legacy call-sites that still mention them don't crash,
# but they always return empty / false.
#
# macOS compatibility: macOS ships bash 3.2 which does not support
# `declare -gA` (associative arrays) or namerefs. We use plain global
# variables instead of associative arrays.

set -uo pipefail

HOOK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HOOK_LIB_DIR/../.." && pwd)"

# Source the file-based infrastructure (graceful degradation if missing).
source "${PLUGIN_ROOT}/scripts/lib/common.sh" 2>/dev/null || true
source "${PLUGIN_ROOT}/scripts/state.sh"     2>/dev/null || true
source "${PLUGIN_ROOT}/scripts/events.sh"    2>/dev/null || true

# ============================================================================
# CONFIGURATION DEFAULTS
# ============================================================================

DEVTEAM_DIR="${DEVTEAM_DIR:-.devteam}"
MAX_ITERATIONS="${DEVTEAM_MAX_ITERATIONS:-100}"
MAX_FAILURES="${DEVTEAM_MAX_FAILURES:-5}"
ECO_MODE="${DEVTEAM_ECO_MODE:-false}"
AUTONOMOUS_MARKER="${DEVTEAM_DIR}/autonomous-mode"

# ============================================================================
# HOOK INITIALIZATION (L1 fix)
# ============================================================================
# Was calling _auto_init_database on every hook invocation. The database
# no longer exists (v6.2 file-based) and there is nothing to initialize.
init_hook() {
    local hook_name="${1:-unknown}"
    export CURRENT_HOOK="$hook_name"
    mkdir -p "$DEVTEAM_DIR" 2>/dev/null || true
}

# ============================================================================
# LOGGING (delegates to scripts/lib/common.sh if available)
# ============================================================================

if ! declare -f log_debug &>/dev/null; then
    log_debug() { echo "[debug] [$1] $2" >&2; }
    log_info()  { echo "[info]  [$1] $2" >&2; }
    log_warn()  { echo "[warn]  [$1] $2" >&2; }
    log_error() { echo "[error] [$1] $2" >&2; }
fi

# ============================================================================
# HOT-PATH CACHE (M1 fix)
# ============================================================================
# iteration, failures, model, session_id, task_id all change rarely within
# a single hook event. Read them once per hook invocation and reuse, instead
# of re-querying the frontmatter for each consumer.

_DEVTEAM_CACHE_SESSION_ID=""
_DEVTEAM_CACHE_TASK_ID=""
_DEVTEAM_CACHE_ITERATION=""
_DEVTEAM_CACHE_FAILURES=""
_DEVTEAM_CACHE_MODEL=""
_DEVTEAM_CACHE_PHASE=""
_DEVTEAM_CACHE_MAX_ITER=""

cache_clear() {
    _DEVTEAM_CACHE_SESSION_ID=""
    _DEVTEAM_CACHE_TASK_ID=""
    _DEVTEAM_CACHE_ITERATION=""
    _DEVTEAM_CACHE_FAILURES=""
    _DEVTEAM_CACHE_MODEL=""
    _DEVTEAM_CACHE_PHASE=""
    _DEVTEAM_CACHE_MAX_ITER=""
}

cache_get() {
    case "$1" in
        session_id) printf '%s' "$_DEVTEAM_CACHE_SESSION_ID" ;;
        task_id)    printf '%s' "$_DEVTEAM_CACHE_TASK_ID" ;;
        iteration)  printf '%s' "$_DEVTEAM_CACHE_ITERATION" ;;
        failures)   printf '%s' "$_DEVTEAM_CACHE_FAILURES" ;;
        model)      printf '%s' "$_DEVTEAM_CACHE_MODEL" ;;
        phase)      printf '%s' "$_DEVTEAM_CACHE_PHASE" ;;
        max_iter)   printf '%s' "$_DEVTEAM_CACHE_MAX_ITER" ;;
    esac
}

cache_set() {
    case "$1" in
        session_id) _DEVTEAM_CACHE_SESSION_ID="$2" ;;
        task_id)    _DEVTEAM_CACHE_TASK_ID="$2" ;;
        iteration)  _DEVTEAM_CACHE_ITERATION="$2" ;;
        failures)   _DEVTEAM_CACHE_FAILURES="$2" ;;
        model)      _DEVTEAM_CACHE_MODEL="$2" ;;
        phase)      _DEVTEAM_CACHE_PHASE="$2" ;;
        max_iter)   _DEVTEAM_CACHE_MAX_ITER="$2" ;;
    esac
}

# Prime the cache for the hot values used by PreToolUse / PostToolUse.
prime_hot_cache() {
    cache_clear
    local sid; sid=$(get_current_session_id 2>/dev/null || echo "")
    cache_set session_id "$sid"
    if [[ -n "$sid" ]]; then
        local file="${STATE_DIR:-.devteam/state}/sessions/${sid}.md"
        if [[ -f "$file" ]]; then
            cache_set task_id   "$(get_frontmatter_value "$file" current_task_id 2>/dev/null)"
            cache_set iteration "$(get_frontmatter_value "$file" current_iteration 2>/dev/null)"
            cache_set failures  "$(get_frontmatter_value "$file" consecutive_failures 2>/dev/null)"
            cache_set model     "$(get_frontmatter_value "$file" current_model 2>/dev/null)"
            cache_set phase     "$(get_frontmatter_value "$file" current_phase 2>/dev/null)"
            cache_set max_iter  "$(get_frontmatter_value "$file" max_iterations 2>/dev/null)"
        fi
    fi
    [[ -z "$(cache_get iteration)" ]] && cache_set iteration "0"
    [[ -z "$(cache_get failures)" ]]  && cache_set failures "0"
    [[ -z "$(cache_get model)" ]]     && cache_set model "sonnet"
    [[ -z "$(cache_get max_iter)" ]]  && cache_set max_iter "$MAX_ITERATIONS"
}

# ============================================================================
# SESSION & STATE ACCESSORS (file-based via state.sh)
# ============================================================================

get_current_session() { get_current_session_id 2>/dev/null; }
get_current_task()    { get_current_task 2>/dev/null; }

get_current_iteration() {
    local cached; cached=$(cache_get iteration)
    [[ -n "$cached" ]] && { echo "$cached"; return; }
    get_state "current_iteration" "0"
}

get_consecutive_failures() {
    local cached; cached=$(cache_get failures)
    [[ -n "$cached" ]] && { echo "$cached"; return; }
    get_state "consecutive_failures" "0"
}

get_current_model() {
    local cached; cached=$(cache_get model)
    [[ -n "$cached" ]] && { echo "$cached"; return; }
    get_state "current_model" "sonnet"
}

# increment_failures / reset_failures — state.sh already defines these
# (lock-protected, markdown frontmatter writes). When state.sh is sourced,
# those are the ones we want — DO NOT redefine. When state.sh is NOT
# sourced (degraded mode), provide minimal direct-edit fallbacks.
if [[ -z "${STATE_DIR:-}" ]]; then
    increment_failures() {
        local sid file current new
        sid=$(get_current_session_id 2>/dev/null || echo "")
        [[ -z "$sid" ]] && return
        file="${DEVTEAM_DIR:-.devteam}/state/sessions/${sid}.md"
        [[ ! -f "$file" ]] && return
        current=$(awk -F': *' '/^consecutive_failures:/{print $2; exit}' "$file" 2>/dev/null | tr -d ' \r\n')
        [[ -z "$current" ]] && current=0
        new=$((current + 1))
        sed "s|^consecutive_failures:.*|consecutive_failures: ${new}|" "$file" > "${file}.tmp"
        mv "${file}.tmp" "$file"
    }
    reset_failures() {
        local sid file
        sid=$(get_current_session_id 2>/dev/null || echo "")
        [[ -z "$sid" ]] && return
        file="${DEVTEAM_DIR:-.devteam}/state/sessions/${sid}.md"
        [[ ! -f "$file" ]] && return
        sed "s|^consecutive_failures:.*|consecutive_failures: 0|" "$file" > "${file}.tmp"
        mv "${file}.tmp" "$file"
    }
fi

# ============================================================================
# CONTEXT INJECTION (M9 fix)
# ============================================================================

inject_system_message() {
    local id="$1"
    local message="$2"

    if command -v jq &>/dev/null; then
        local filter='{id:$id,type:"system",message:$msg}'
        jq -n --arg id "devteam-${id}" --arg msg "$message" "$filter"
    else
        local escaped="${message//\\/\\\\}"
        escaped="${escaped//\"/\\\"}"
        # Replace newlines / carriage returns / tabs using printf-generated
        # literals. Avoids the $'\n' syntax which inside ${var//...} can
        # confuse some bash versions.
        local nl cr tab
        nl=$(printf '\n')
        cr=$(printf '\r')
        tab=$(printf '\t')
        escaped="${escaped//${nl}/\\n}"
        escaped="${escaped//${cr}/\\r}"
        escaped="${escaped//${tab}/\\t}"
        printf '{"id":"devteam-%s","type":"system","message":"%s"}\n' "$id" "$escaped"
    fi
}

# ============================================================================
# SCOPE CHECKING (M10 fix)
# ============================================================================

file_in_scope() {
    local file_path="$1"

    local scope_file="${DEVTEAM_DIR}/task-scope.txt"
    [[ -f "$scope_file" ]] || return 0

    local normalized
    normalized=$(realpath -m "$file_path" 2>/dev/null || echo "$file_path")

    while IFS= read -r scope_pattern; do
        [[ -z "$scope_pattern" ]] && continue
        [[ "$scope_pattern" == \#* ]] && continue

        if [[ "$file_path" == "$scope_pattern" ]] \
            || [[ "$normalized" == "$scope_pattern" ]] \
            || [[ "$file_path" == "$scope_pattern"/* ]] \
            || [[ "$normalized" == "$scope_pattern"/* ]]; then
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
# EVENT LOGGING (delegates to events.sh's log_event)
# ============================================================================

log_event_to_db() {
    local event_type="$1"
    local category="$2"
    local message="$3"
    local data="${4:-"{}"}"

    if declare -f log_event &>/dev/null; then
        log_event "$event_type" "$category" "$message" "$data" 2>/dev/null || true
    fi
}

# ============================================================================
# MCP NOTIFICATION (L2 fix)
# ============================================================================

mcp_notify() {
    local event="$1"
    local data="${2:-"{}"}"

    local sock="${DEVTEAM_DIR}/mcp.sock"
    [[ -S "$sock" ]] || return 0
    command -v socat &>/dev/null || return 0

    local payload
    if command -v jq &>/dev/null; then
        payload=$(jq -n --arg ev "$event" --argjson d "$data" '{event: $ev, data: $d}')
    else
        payload=$(printf '{"event":"%s","data":%s}\n' "$event" "$data")
    fi
    printf '%s' "$payload" | socat - UNIX-CONNECT:"$sock" 2>/dev/null || true
}

# ============================================================================
# QWEN CONTEXT
# ============================================================================

get_qwen_context() {
    local session_id; session_id=$(get_current_session)
    local task_id; task_id=$(get_current_task)
    local iteration; iteration=$(get_current_iteration)
    local failures; failures=$(get_consecutive_failures)
    local model; model=$(get_current_model)

    if command -v jq &>/dev/null; then
        local filter='{session:$session,task:$task,iteration:$iteration,failures:$failures,model:$model,hook:$hook}'
        jq -n \
            --arg session "${session_id:-}" \
            --arg task "${task_id:-}" \
            --argjson iteration "${iteration:-0}" \
            --argjson failures "${failures:-0}" \
            --arg model "${model:-sonnet}" \
            --arg hook "${CURRENT_HOOK:-unknown}" \
            "$filter"
    else
        local safe_s="${session_id//\"/\\\"}"
        local safe_t="${task_id//\"/\\\"}"
        printf '{"session":"%s","task":"%s","iteration":%s,"failures":%s,"model":"%s","hook":"%s"}\n' \
            "${safe_s:-}" "${safe_t:-}" "${iteration:-0}" "${failures:-0}" "${model:-sonnet}" "${CURRENT_HOOK:-unknown}"
    fi
}

# ============================================================================
# ESCALATION
# ============================================================================

trigger_escalation() {
    local reason="$1"

    log_warn "${CURRENT_HOOK:-hook}" "Escalation triggered: $reason"
    log_event_to_db "model_escalated" "escalation" "Escalation: $reason" "{\"reason\":\"${reason//\"/\\\"}\"}"

    if declare -f record_escalation &>/dev/null; then
        record_escalation "" "" "$reason" 2>/dev/null || true
    fi
}

# ============================================================================
# AUTONOMOUS MODE & CIRCUIT BREAKER
# ============================================================================

is_autonomous_mode() {
    [[ -f "$AUTONOMOUS_MARKER" ]]
}

is_circuit_breaker_open() {
    local failures
    failures=$(get_consecutive_failures)
    [[ "$failures" =~ ^[0-9]+$ ]] || failures=0
    [[ "$failures" -ge "$MAX_FAILURES" ]]
}

is_max_iterations_reached() {
    local iteration max
    iteration=$(get_current_iteration)
    max=$(cache_get max_iter)
    [[ -z "$max" ]] && max=$(get_state "max_iterations" "$MAX_ITERATIONS")
    [[ "$iteration" =~ ^[0-9]+$ ]] || iteration=0
    [[ "$max" =~ ^[0-9]+$ ]] || max=100
    [[ "$iteration" -ge "$max" ]]
}

# ============================================================================
# CHECKPOINTS (file-based; no SQLite)
# ============================================================================

save_checkpoint() {
    local message="${1:-Auto-checkpoint}"
    local sid file now
    sid=$(get_current_session_id 2>/dev/null || echo "")
    [[ -z "$sid" ]] && return
    file="${STATE_DIR:-.devteam/state}/sessions/${sid}.md"
    [[ ! -f "$file" ]] && return
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    atomic_append "$file" "- ${now} [checkpoint] ${message}"
}

save_exit_checkpoint() {
    log_info "${CURRENT_HOOK:-stop}" "Saving checkpoint before exit"
    save_checkpoint "Auto-checkpoint before exit"
    log_event_to_db "checkpoint_created" "session" "Auto-checkpoint before exit"
}

# ============================================================================
# DATABASE HELPERS (no-op stubs for backward compatibility)
# ============================================================================
# Legacy hook code that still calls db_query / db_exists doesn't break —
# but they always return empty / false because there is no database.

db_exists() { return 1; }

db_query() {
    _warn_db_legacy_once
    echo ""
}

_warn_db_legacy_once() {
    [[ -n "${_DB_LEGACY_WARNED:-}" ]] && return 0
    _DB_LEGACY_WARNED=1
    log_warn "${CURRENT_HOOK:-hook}" "db_query/db_exists called but DevTeam is file-based (no SQLite). Returning empty." >&2 || true
}