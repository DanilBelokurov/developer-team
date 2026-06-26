#!/bin/bash
# DevTeam State Management (v6.2 — file-based, no SQLite)
# Backward-compatible with v6.1 API (set_kv_state, set_state, etc.)
# but storage is now Markdown files in .devteam/state/
#
# Usage: source this file in hooks and commands
#   source "$(dirname "$0")/state.sh"
#
# Storage layout:
#   .devteam/state/
#   ├── current-session.md          # active session pointer
#   ├── sessions/<id>.md            # per-session MD with frontmatter
#   ├── kv/<key>                    # one file per KV key
#   ├── kv/<plan-id>/<key>           # plan-isolated KV
#   ├── events/<date>-events.md     # append-only daily log
#   ├── agent-runs/<run-id>.md      # per-agent-run MD
#   ├── tasks/<TASK-ID>.md          # per-task MD
#   ├── circuit-breaker.md          # circuit breaker state
#   └── abandonment/<session-id>.log # per-session abandonment log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# PATH CONSTANTS
# ============================================================================

# Resolve ROOT (project dir) — defaults to current dir, overridable
ROOT="${ROOT:-$(pwd)}"
STATE_DIR="${ROOT}/.devteam/state"
SESSIONS_DIR="${STATE_DIR}/sessions"
KV_DIR="${STATE_DIR}/kv"
EVENTS_DIR="${STATE_DIR}/events"
TASKS_DIR="${STATE_DIR}/tasks"
AGENT_RUNS_DIR="${STATE_DIR}/agent-runs"
ABANDONMENT_DIR="${STATE_DIR}/abandonment"

# Backward-compat: if a v6.1 .devteam/devteam.db exists, warn and offer migration
LEGACY_DB="${ROOT}/.devteam/devteam.db"

# ============================================================================
# LOGGING (stderr only; stdout reserved for return values)
# ============================================================================

log_info()  { echo "[devteam] $1" >&2; }
log_warn()  { echo "[devteam] $1" >&2; }
log_error() { echo "[devteam] $1" >&2; }
log_debug() { [[ -n "${DEBUG:-}" ]] && echo "[devteam:debug] $1" >&2 || true; }

# ============================================================================
# LOCK PRIMITIVES (H8/H9 fix)
# ============================================================================
# POSIX mkdir is atomic. We don't busy-wait with 100 polls + sleep 0.01;
# we try once, sleep one short interval if needed, and bail out fast.
# Trap is set once at the top with ERR+RETURN+INT+TERM so the lock is
# released on every exit path, including set -e errors.

# Try to acquire a lock by mkdir-ing a sidecar directory.
# Returns 0 on success, 1 on timeout. NEVER blocks more than ~50ms.
acquire_lock() {
    local lockpath="$1"
    if mkdir "$lockpath" 2>/dev/null; then
        return 0
    fi
    # Brief retry: a sibling caller might be holding it for milliseconds.
    # Two attempts × sleep 0.05s max → 100ms worst case, not 1 second.
    sleep 0.05 2>/dev/null || true
    if mkdir "$lockpath" 2>/dev/null; then
        return 0
    fi
    log_error "Lock busy: $lockpath (held by another process)"
    return 1
}

# Release lock by rmdir-ing the sidecar directory.
release_lock() {
    rmdir "$1" 2>/dev/null || true
}

# Internal: perform an action under a lock with a robust trap.
# Args: lockpath, callback-name, [args...]
_with_lock() {
    local lockpath="$1"
    local callback="$2"
    shift 2

    acquire_lock "$lockpath" || return 1

    # Trap covers normal RETURN, errors (ERR), and signals (INT/TERM).
    # The trap release_lock then removes itself so callers further up
    # the stack don't accidentally release a lock they don't own.
    trap "release_lock '$lockpath'; trap - RETURN ERR INT TERM" RETURN ERR INT TERM

    "$callback" "$@"
    local rc=$?

    trap - RETURN ERR INT TERM
    release_lock "$lockpath"
    return $rc
}

# ============================================================================
# ATOMIC FILE OPS
# ============================================================================

# Write content to file atomically. Args: file, content
atomic_write() {
    local file="$1"
    local content="$2"
    mkdir -p "$(dirname "$file")"
    printf '%s' "$content" > "${file}.tmp"
    mv "${file}.tmp" "$file"
}

# Append to file atomically. Args: file, content
atomic_append() {
    local file="$1"
    local content="$2"
    local lockpath="${file}.lock"
    mkdir -p "$(dirname "$file")"

    _with_lock "$lockpath" _do_atomic_append "$content" "$file"
}

_do_atomic_append() {
    # Args: content, file
    printf '%s\n' "$1" >> "$2"
}

# Read frontmatter value from MD file. Args: file, key
get_frontmatter_value() {
    local file="$1"
    local key="$2"
    [[ ! -f "$file" ]] && return 1
    awk -v key="^${key}:" '
        /^---$/ { c++; next }
        c == 1 && $0 ~ key { sub(key, ""); sub(/^[ \t]+/, ""); print; exit }
    ' "$file" 2>/dev/null
}

# Update frontmatter value in MD file. Args: file, key, value
set_frontmatter_value() {
    local file="$1"
    local key="$2"
    local value="$3"
    [[ ! -f "$file" ]] && return 1

    local lockpath="${file}.lock"
    _with_lock "$lockpath" _do_set_frontmatter_value "$file" "$key" "$value"
}

_do_set_frontmatter_value() {
    local file="$1"
    local key="$2"
    local value="$3"
    if grep -q "^${key}:" "$file"; then
        # macOS sed -i requires -i '' ; on Linux '' is not accepted.
        # Use a tmp file + mv to be portable.
        sed "s|^${key}:.*|${key}: ${value}|" "$file" > "${file}.tmp"
        mv "${file}.tmp" "$file"
    else
        awk -v key="$key" -v val="$value" '
            /^---$/ { c++; if (c == 2) { print key": "val; } print; next }
            { print }
        ' "$file" > "${file}.tmp"
        mv "${file}.tmp" "$file"
    fi
}

# ============================================================================
# INITIALIZATION (called by state-init.sh; idempotent)
# ============================================================================

ensure_state_dir() {
    [[ -d "$SESSIONS_DIR" ]] || mkdir -p "$SESSIONS_DIR"
    [[ -d "$KV_DIR" ]]      || mkdir -p "$KV_DIR"
    [[ -d "$EVENTS_DIR" ]]   || mkdir -p "$EVENTS_DIR"
    [[ -d "$TASKS_DIR" ]]    || mkdir -p "$TASKS_DIR"
    [[ -d "$AGENT_RUNS_DIR" ]] || mkdir -p "$AGENT_RUNS_DIR"
    [[ -d "$ABANDONMENT_DIR" ]] || mkdir -p "$ABANDONMENT_DIR"

    [[ -f "${STATE_DIR}/current-session.md" ]] || \
        atomic_write "${STATE_DIR}/current-session.md" ""

    [[ -f "${STATE_DIR}/circuit-breaker.md" ]] || atomic_write "${STATE_DIR}/circuit-breaker.md" "$(cat <<'EOF'
---
state: closed
consecutive_failures: 0
max_consecutive_failures: 5
last_failure_at: ~
last_success_at: ~
opened_at: ~
half_open_at: ~
---
EOF
)"

    [[ -f "${STATE_DIR}/gates.md" ]] || atomic_write "${STATE_DIR}/gates.md" "# Quality Gates"$(printf '\n')

    local today
    today=$(date +%Y-%m-%d)
    local events_file="${EVENTS_DIR}/${today}-events.md"
    [[ -f "$events_file" ]] || atomic_write "$events_file" "# Events ${today}"$(printf '\n')
}

warn_legacy_db() {
    [[ -f "$LEGACY_DB" ]] || return 0
    log_warn "Legacy SQLite DB found: $LEGACY_DB (devteam v6.2 is file-based — see scripts/state-migrate-v61-to-v62.sh)"
}

# ============================================================================
# SESSION MANAGEMENT
# ============================================================================

generate_session_id() {
    local ts rand
    ts=$(date +%Y%m%d-%H%M%S)
    if command -v xxd &>/dev/null; then
        rand=$(head -c4 /dev/urandom | xxd -p 2>/dev/null)
    else
        rand=$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')
    fi
    echo "session-${ts}-${rand}"
}

# Start a new session
# Args: command, command_type, [execution_mode], [max_iterations]
start_session() {
    local command="$1"
    local command_type="$2"
    local execution_mode="${3:-normal}"
    local max_iterations="${4:-${DEVTEAM_MAX_ITERATIONS:-100}}"

    if [[ -z "$command" ]]; then
        log_error "Command cannot be empty"
        return 1
    fi

    ensure_state_dir
    warn_legacy_db

    local session_id
    session_id=$(generate_session_id)
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local body
    body=$(cat <<EOF
---
id: ${session_id}
started_at: ${now}
ended_at: ~
command: ${command}
command_type: ${command_type}
status: running
current_phase: initializing
current_agent: ~
current_model: sonnet
current_iteration: 0
current_task_id: ~
sprint_id: ~
consecutive_failures: 0
circuit_breaker_state: closed
execution_mode: ${execution_mode}
max_iterations: ${max_iterations}
total_tokens_input: 0
total_tokens_output: 0
total_cost_cents: 0
bug_council_activated: FALSE
bug_council_reason: ~
---

# Session ${session_id}

## State
- pipeline.active: true

## Activity
- ${now} [start] command received
EOF
)

    atomic_write "${SESSIONS_DIR}/${session_id}.md" "$body"
    atomic_write "${STATE_DIR}/current-session.md" "session/${session_id}"

    log_info "Session started: $session_id"
    echo "$session_id"
}

end_session() {
    local status="${1:-completed}"
    local exit_reason="${2:-Success}"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local session_id
    session_id=$(get_current_session_id)
    if [[ -z "$session_id" ]]; then
        log_error "No active session"
        return 1
    fi

    local file="${SESSIONS_DIR}/${session_id}.md"
    [[ ! -f "$file" ]] && { log_error "Session file not found: $file"; return 1; }

    set_frontmatter_value "$file" "status" "$status"
    set_frontmatter_value "$file" "ended_at" "$now"
    set_frontmatter_value "$file" "exit_reason" "$exit_reason"

    log_info "Session ended: $session_id ($status)"
}

get_current_session_id() {
    [[ ! -f "${STATE_DIR}/current-session.md" ]] && return 0
    local ref
    ref=$(cat "${STATE_DIR}/current-session.md" 2>/dev/null)
    [[ -z "$ref" ]] && return 0
    [[ "$ref" == session/* ]] && echo "${ref#session/}" || echo ""
}

is_session_running() {
    local id
    id=$(get_current_session_id)
    [[ -z "$id" ]] && return 1
    local file="${SESSIONS_DIR}/${id}.md"
    [[ ! -f "$file" ]] && return 1
    local status
    status=$(get_frontmatter_value "$file" "status")
    [[ "$status" == "running" ]]
}

get_session_json() {
    local id="${1:-$(get_current_session_id)}"
    local file="${SESSIONS_DIR}/${id}.md"
    [[ ! -f "$file" ]] && return 1

    local id_v started_at ended_at command command_type status phase iter fails cb mode tokens_in tokens_out cost
    id_v=$(get_frontmatter_value "$file" "id")
    started_at=$(get_frontmatter_value "$file" "started_at")
    ended_at=$(get_frontmatter_value "$file" "ended_at")
    command=$(get_frontmatter_value "$file" "command")
    command_type=$(get_frontmatter_value "$file" "command_type")
    status=$(get_frontmatter_value "$file" "status")
    phase=$(get_frontmatter_value "$file" "current_phase")
    iter=$(get_frontmatter_value "$file" "current_iteration")
    fails=$(get_frontmatter_value "$file" "consecutive_failures")
    cb=$(get_frontmatter_value "$file" "circuit_breaker_state")
    mode=$(get_frontmatter_value "$file" "execution_mode")
    tokens_in=$(get_frontmatter_value "$file" "total_tokens_input")
    tokens_out=$(get_frontmatter_value "$file" "total_tokens_output")
    cost=$(get_frontmatter_value "$file" "total_cost_cents")

    cat <<EOF
{"id":"$id_v","started_at":"$started_at","ended_at":"$ended_at","command":"$command","command_type":"$command_type","status":"$status","current_phase":"$phase","current_iteration":${iter:-0},"consecutive_failures":${fails:-0},"circuit_breaker_state":"$cb","execution_mode":"$mode","total_tokens_input":${tokens_in:-0},"total_tokens_output":${tokens_out:-0},"total_cost_cents":${cost:-0}}
EOF
}

# ============================================================================
# KV STATE
# ============================================================================

# Set a key-value pair. Args: key, value, [plan_id]
set_kv_state() {
    local key="$1"
    local value="$2"
    local plan_id="${3:-}"
    [[ -z "$key" ]] && { log_error "Key cannot be empty"; return 1; }
    ensure_state_dir

    if [[ -n "$plan_id" ]]; then
        mkdir -p "${KV_DIR}/${plan_id}"
        atomic_write "${KV_DIR}/${plan_id}/${key}" "$value"
    else
        atomic_write "${KV_DIR}/${key}" "$value"
    fi
}

# Get a key-value pair. Args: key, [default], [plan_id]
get_kv_state() {
    local key="$1"
    local default="${2:-}"
    local plan_id="${3:-}"
    local val

    if [[ -n "$plan_id" ]]; then
        val=$(cat "${KV_DIR}/${plan_id}/${key}" 2>/dev/null)
    else
        val=$(cat "${KV_DIR}/${key}" 2>/dev/null)
    fi
    [[ -n "$val" ]] && echo "$val" || echo "$default"
}

delete_kv_state() {
    local key="$1"
    local plan_id="${2:-}"
    if [[ -n "$plan_id" ]]; then
        rm -f "${KV_DIR}/${plan_id}/${key}" 2>/dev/null
    else
        rm -f "${KV_DIR}/${key}" 2>/dev/null
    fi
}

# ============================================================================
# STATE GETTERS/SETTERS
# ============================================================================

set_state() {
    local field="$1"
    local value="$2"
    local session_id="${3:-}"

    [[ -z "$field" ]] && { log_error "Field name required"; return 1; }

    [[ -z "$session_id" ]] && session_id=$(get_current_session_id)
    [[ -z "$session_id" ]] && { log_error "No active session"; return 1; }

    local file="${SESSIONS_DIR}/${session_id}.md"
    [[ ! -f "$file" ]] && { log_error "Session file not found: $file"; return 1; }

    set_frontmatter_value "$file" "$field" "$value"
}

get_state() {
    local field="$1"
    local default="${2:-}"
    local session_id
    session_id=$(get_current_session_id)
    [[ -z "$session_id" ]] && { echo "$default"; return 0; }
    local file="${SESSIONS_DIR}/${session_id}.md"
    [[ ! -f "$file" ]] && { echo "$default"; return 0; }
    local val
    val=$(get_frontmatter_value "$file" "$field")
    [[ -n "$val" ]] && echo "$val" || echo "$default"
}

# Convenience accessors
get_current_phase()       { get_state "current_phase"; }
get_current_agent()       { get_state "current_agent"; }
get_current_model()       { get_state "current_model" "sonnet"; }
get_current_iteration()   { get_state "current_iteration" "0"; }
get_current_task()        { get_state "current_task_id"; }
get_consecutive_failures(){ get_state "consecutive_failures" "0"; }
get_execution_mode()      { get_state "execution_mode" "normal"; }

is_eco_mode() { [[ "$(get_execution_mode)" == "eco" ]]; }

is_bug_council_active() { [[ "$(get_state bug_council_activated)" == "TRUE" ]]; }

set_phase() { set_state "current_phase" "$1"; }
set_current_agent() { [[ -z "$1" ]] && { log_error "Agent name cannot be empty"; return 1; }; set_state "current_agent" "$1"; }
set_current_model() { set_state "current_model" "$1"; }
set_current_task()  { set_state "current_task_id" "$1"; }

# ============================================================================
# ITERATION TRACKING
# ============================================================================

increment_iteration() {
    local current
    current=$(get_current_iteration)
    local new=$((current + 1))
    set_state "current_iteration" "$new"
    log_debug "Iteration incremented: $current → $new"
}

increment_failures() {
    local current
    current=$(get_consecutive_failures)
    local new=$((current + 1))
    set_state "consecutive_failures" "$new"
    log_debug "Consecutive failures: $current → $new"
}

reset_failures() {
    set_state "consecutive_failures" "0"
    log_debug "Consecutive failures reset to 0"
}

# ============================================================================
# CIRCUIT BREAKER
# ============================================================================

get_circuit_breaker_state() {
    [[ ! -f "${STATE_DIR}/circuit-breaker.md" ]] && { echo "closed"; return; }
    awk '/^state:/ {sub(/^state: */, ""); sub(/ *$/, ""); print; exit}' \
        "${STATE_DIR}/circuit-breaker.md" 2>/dev/null || echo "closed"
}

set_circuit_breaker_state() {
    local new_state="$1"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local file="${STATE_DIR}/circuit-breaker.md"
    [[ ! -f "$file" ]] && return 1

    local lockpath="${file}.lock"
    _with_lock "$lockpath" _do_set_cb_state "$file" "$new_state" "$now"
}

_do_set_cb_state() {
    local file="$1"
    local new_state="$2"
    local now="$3"

    sed "s|^state:.*|state: ${new_state}|" "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"

    if [[ "$new_state" == "open" ]]; then
        if grep -q "^opened_at:" "$file"; then
            sed "s|^opened_at:.*|opened_at: ${now}|" "$file" > "${file}.tmp"
        else
            awk -v ts="$now" '/^---$/{c++; if(c==2){print "opened_at: "ts} print; next} {print}' \
                "$file" > "${file}.tmp"
        fi
        mv "${file}.tmp" "$file"
    elif [[ "$new_state" == "half-open" ]]; then
        if grep -q "^half_open_at:" "$file"; then
            sed "s|^half_open_at:.*|half_open_at: ${now}|" "$file" > "${file}.tmp"
            mv "${file}.tmp" "$file"
        fi
    fi
}

should_trip_circuit_breaker() {
    local current
    current=$(get_consecutive_failures)
    local max
    max=$(get_state "max_consecutive_failures" "5")
    [[ "$current" -ge "$max" ]]
}

trip_circuit_breaker() {
    set_circuit_breaker_state "open"
    log_warn "Circuit breaker tripped (consecutive failures: $(get_consecutive_failures))"
}

reset_circuit_breaker() {
    set_circuit_breaker_state "closed"
    set_state "consecutive_failures" "0"
    log_info "Circuit breaker reset to closed"
}

# ============================================================================
# MODEL ESCALATION
# ============================================================================

MODEL_TIERS=("haiku" "sonnet" "opus")

get_next_model() {
    local current="${1:-$(get_current_model)}"
    [[ -z "$current" ]] && current="haiku"
    for i in "${!MODEL_TIERS[@]}"; do
        if [[ "${MODEL_TIERS[$i]}" == "$current" ]]; then
            local next_idx=$((i + 1))
            if [[ $next_idx -lt ${#MODEL_TIERS[@]} ]]; then
                echo "${MODEL_TIERS[$next_idx]}"
            else
                echo "opus"
            fi
            return
        fi
    done
    echo "sonnet"
}

get_previous_model() {
    local current="${1:-$(get_current_model)}"
    [[ -z "$current" ]] && { echo "haiku"; return; }
    for i in "${!MODEL_TIERS[@]}"; do
        if [[ "${MODEL_TIERS[$i]}" == "$current" ]]; then
            local prev_idx=$((i - 1))
            if [[ $prev_idx -ge 0 ]]; then
                echo "${MODEL_TIERS[$prev_idx]}"
            else
                echo "haiku"
            fi
            return
        fi
    done
    echo "haiku"
}

record_escalation() {
    local from_model="$1"
    local to_model="$2"
    local reason="${3:-}"

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local today
    today=$(date +%Y-%m-%d)
    local events_file="${EVENTS_DIR}/${today}-events.md"

    atomic_append "$events_file" "## ${now} — model_escalated
- session_id: $(get_current_session_id)
- from: $from_model
- to: $to_model
- reason: $reason"

    set_current_model "$to_model"
}

# ============================================================================
# BUG COUNCIL
# ============================================================================

activate_bug_council() {
    local reason="$1"
    [[ -z "$reason" ]] && { log_error "Reason cannot be empty"; return 1; }

    set_state "bug_council_activated" "TRUE"
    set_state "bug_council_reason" "$reason"

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local today
    today=$(date +%Y-%m-%d)
    local events_file="${EVENTS_DIR}/${today}-events.md"
    atomic_append "$events_file" "## ${now} — bug_council_activated
- session_id: $(get_current_session_id)
- reason: $reason"

    log_info "Bug council activated: $reason"
}

# ============================================================================
# TOKENS & COST
# ============================================================================

add_tokens() {
    local input="$1"
    local output="$2"

    local current_in
    current_in=$(get_state "total_tokens_input" "0")
    local current_out
    current_out=$(get_state "total_tokens_output" "0")

    set_state "total_tokens_input" "$((current_in + input))"
    set_state "total_tokens_output" "$((current_out + output))"

    local input_rate="${INPUT_TOKEN_RATE_CENTS:-3}"
    local output_rate="${OUTPUT_TOKEN_RATE_CENTS:-15}"
    local cost=$(( input * input_rate / 1000 + output * output_rate / 1000 ))

    local current_cost
    current_cost=$(get_state "total_cost_cents" "0")
    set_state "total_cost_cents" "$((current_cost + cost))"
}

get_total_cost_dollars() {
    local cents
    cents=$(get_state "total_cost_cents" "0")
    awk "BEGIN { printf \"%.4f\", $cents / 100 }"
}

# ============================================================================
# PLANS & SPRINTS
# ============================================================================

set_active_plan() {
    local plan_id="$1"
    [[ -z "$plan_id" ]] && { log_error "Plan ID required"; return 1; }
    set_kv_state "active_plan" "$plan_id"
}

set_active_sprint() {
    local sprint_id="$1"
    [[ -z "$sprint_id" ]] && { log_error "Sprint ID required"; return 1; }
    set_kv_state "active_sprint" "$sprint_id"
}

# ============================================================================
# SESSION SUMMARY
# ============================================================================

get_session_summary() {
    local id="${1:-$(get_current_session_id)}"
    local file="${SESSIONS_DIR}/${id}.md"
    [[ ! -f "$file" ]] && { log_error "Session not found: $id"; return 1; }

    cat <<EOF
=== Session Summary ===
ID:           $id
Status:       $(get_frontmatter_value "$file" "status")
Phase:        $(get_frontmatter_value "$file" "current_phase")
Iteration:    $(get_frontmatter_value "$file" "current_iteration")
Failures:     $(get_frontmatter_value "$file" "consecutive_failures")
Model:        $(get_frontmatter_value "$file" "current_model")
Started:      $(get_frontmatter_value "$file" "started_at")
Tokens in:    $(get_frontmatter_value "$file" "total_tokens_input")
Tokens out:   $(get_frontmatter_value "$file" "total_tokens_output")
Cost (cents): $(get_frontmatter_value "$file" "total_cost_cents")
Cost (\$):    $(get_total_cost_dollars)
EOF
}

# ============================================================================
# ABANDONMENT TRACKING (M4 fix: per-session, not global)
# ============================================================================

# Append an abandonment attempt to the per-session log.
# Args: detection_type, pattern
log_abandonment_attempt() {
    local detection_type="$1"
    local pattern="$2"
    local session_id
    session_id=$(get_current_session_id)
    [[ -z "$session_id" ]] && return 1
    local log_file="${ABANDONMENT_DIR}/${session_id}.log"
    local now
    now=$(date -Iseconds)
    atomic_append "$log_file" "[${now}] ${detection_type}: '${pattern}'"
}

# Count abandonment attempts in the CURRENT session only (not global).
# This replaces the old `wc -l < abandonment-attempts.log` which leaked
# across sessions.
count_session_abandonment_attempts() {
    local session_id
    session_id=$(get_current_session_id)
    [[ -z "$session_id" ]] && { echo "0"; return; }
    local log_file="${ABANDONMENT_DIR}/${session_id}.log"
    [[ -f "$log_file" ]] || { echo "0"; return; }
    wc -l < "$log_file" 2>/dev/null | tr -d ' ' || echo "0"
}

# ============================================================================
# ITERATION LIMITS
# ============================================================================

is_max_iterations_reached() {
    local current
    current=$(get_current_iteration)
    local max
    max=$(get_state "max_iterations" "${DEVTEAM_MAX_ITERATIONS:-100}")
    [[ "$current" -ge "$max" ]]
}