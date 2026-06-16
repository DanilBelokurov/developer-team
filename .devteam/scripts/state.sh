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
#   ├── events/<date>-events.md     # append-only daily log
#   ├── agent-runs/<run-id>.md      # per-agent-run MD
#   ├── tasks/<TASK-ID>.md          # per-task MD
#   ├── gates.md                    # quality gate log
#   └── circuit-breaker.md          # circuit breaker state

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Note: scripts/lib/common.sh is from v6.1 (SQLite-era) and requires bash 4+.
# We don't source it here. v6.2 state.sh is self-contained (uses file ops).

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

# Backward-compat: if a v6.1 .devteam/devteam.db exists, warn and offer migration
LEGACY_DB="${ROOT}/.devteam/devteam.db"

# ============================================================================
# LOGGING (kept from common.sh; re-defined here for self-containment)
# ============================================================================

# Logging — all to stderr so stdout is reserved for function return values
log_info()  { echo "[devteam] $1" >&2; }
log_warn()  { echo "[devteam] $1" >&2; }
log_error() { echo "[devteam] $1" >&2; }
log_debug() { [[ -n "${DEBUG:-}" ]] && echo "[devteam:debug] $1" >&2 || true; }

# ============================================================================
# ATOMIC FILE OPS (mkdir-lock based, POSIX-portable)
# ============================================================================

# Try to acquire a lock by mkdir-ing a sidecar directory. mkdir is atomic
# on POSIX (returns EEXIST if dir exists). If acquisition fails after
# 100 attempts (~1s), log error and return 1.
# Args: lockpath (e.g. /path/to/file.lock)
acquire_lock() {
    local lockpath="$1"
    local i=0
    while ! mkdir "$lockpath" 2>/dev/null; do
        i=$((i + 1))
        if [ $i -gt 100 ]; then
            log_error "Lock timeout: $lockpath"
            return 1
        fi
        sleep 0.01 2>/dev/null || true
    done
}

# Release lock by rmdir-ing the sidecar directory.
# Args: lockpath
release_lock() {
    rmdir "$1" 2>/dev/null || true
}

# Write content to file atomically. Uses mkdir-based lock + atomic rename.
# Args: file, content
atomic_write() {
    local file="$1"
    local content="$2"
    local lockpath="${file}.lock"

    acquire_lock "$lockpath" || return 1
    trap "release_lock '$lockpath'" RETURN
    mkdir -p "$(dirname "$file")"
    printf '%s' "$content" > "${file}.tmp"
    mv "${file}.tmp" "$file"
    release_lock "$lockpath"
    trap - RETURN
}

# Append to file atomically. Args: file, content
atomic_append() {
    local file="$1"
    local content="$2"
    local lockpath="${file}.lock"

    acquire_lock "$lockpath" || return 1
    trap "release_lock '$lockpath'" RETURN
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "$content" >> "$file"
    release_lock "$lockpath"
    trap - RETURN
}

# Read frontmatter value from MD file. Args: file, key
get_frontmatter_value() {
    local file="$1"
    local key="$2"
    [[ ! -f "$file" ]] && return 1
    # YAML frontmatter is between first --- and second ---
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
    acquire_lock "$lockpath" || return 1
    trap "release_lock '$lockpath'" RETURN
    # Replace the line in-place; preserve other lines
    if grep -q "^${key}:" "$file"; then
        sed -i.bak "s|^${key}:.*|${key}: ${value}|" "$file"
        rm -f "${file}.bak"
    else
        # Insert after the second --- (end of frontmatter)
        awk -v key="$key" -v val="$value" '
            /^---$/ { c++; if (c == 2) { print key": "val; } print; next }
            { print }
        ' "$file" > "${file}.tmp"
        mv "${file}.tmp" "$file"
    fi
    release_lock "$lockpath"
    trap - RETURN
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

    # Touch current-session.md if missing
    [[ -f "${STATE_DIR}/current-session.md" ]] || \
        atomic_write "${STATE_DIR}/current-session.md" ""

    # Initialize circuit-breaker if missing
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

    # Initialize gates.md if missing
    [[ -f "${STATE_DIR}/gates.md" ]] || atomic_write "${STATE_DIR}/gates.md" "# Quality Gates"$(printf '\n')

    # Touch today's events file
    local today
    today=$(date +%Y-%m-%d)
    local events_file="${EVENTS_DIR}/${today}-events.md"
    [[ -f "$events_file" ]] || atomic_write "$events_file" "# Events ${today}"$(printf '\n')
}

# Warn about legacy v6.1 SQLite DB if present
warn_legacy_db() {
    [[ -f "$LEGACY_DB" ]] || return 0
    log_warn "Legacy SQLite DB found: $LEGACY_DB"
    log_warn "DevTeam v6.2 uses file-based state at $STATE_DIR/"
    log_warn "Migrate with: bash scripts/state-migrate-v61-to-v62.sh"
}

# ============================================================================
# SESSION MANAGEMENT
# ============================================================================

# Generate a unique session ID
generate_session_id() {
    local ts rand
    ts=$(date +%Y%m%d-%H%M%S)
    rand=$(head -c4 /dev/urandom | xxd -p 2>/dev/null || echo "$RANDOM")
    echo "session-${ts}-${rand}"
}

# Start a new session
# Args: command, command_type, [execution_mode]
start_session() {
    local command="$1"
    local command_type="$2"
    local execution_mode="${3:-normal}"

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
current_iteration: 0
max_iterations: 10
consecutive_failures: 0
circuit_breaker_state: closed
execution_mode: ${execution_mode}
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

# End the current session
# Args: [status], [exit_reason]
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

# Get current session ID
get_current_session_id() {
    [[ ! -f "${STATE_DIR}/current-session.md" ]] && return 0
    local ref
    ref=$(cat "${STATE_DIR}/current-session.md" 2>/dev/null)
    [[ -z "$ref" ]] && return 0
    [[ "$ref" == session/* ]] && echo "${ref#session/}" || echo ""
}

# Check if session is running
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

# Render session as JSON (backward-compat with v6.1 callers that parse JSON)
get_session_json() {
    local id="${1:-$(get_current_session_id)}"
    local file="${SESSIONS_DIR}/${id}.md"
    [[ ! -f "$file" ]] && return 1

    # Build JSON from frontmatter
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
# KV STATE (backward-compat names: set_kv_state, get_kv_state)
# ============================================================================

# Set a key-value pair
# Args: key, value, [session_id]
set_kv_state() {
    local key="$1"
    local value="$2"
    [[ -z "$key" ]] && { log_error "Key cannot be empty"; return 1; }
    ensure_state_dir
    atomic_write "${KV_DIR}/${key}" "$value"
}

# Get a key-value pair
# Args: key, [default]
get_kv_state() {
    local key="$1"
    local default="${2:-}"
    local val
    val=$(cat "${KV_DIR}/${key}" 2>/dev/null)
    [[ -n "$val" ]] && echo "$val" || echo "$default"
}

# Delete a key-value pair
delete_kv_state() {
    local key="$1"
    rm -f "${KV_DIR}/${key}" 2>/dev/null
}

# ============================================================================
# STATE GETTERS/SETTERS (backward-compat with v6.1)
# These read/write frontmatter of the current session file.
# ============================================================================

# Generic set: field, value, [session_id]
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

# Generic get: field, [default]
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
get_current_phase()      { get_state "current_phase"; }
get_current_agent()      { get_state "current_agent"; }
get_current_model()      { get_state "current_model"; }
get_current_iteration()   { get_state "current_iteration" "0"; }
get_consecutive_failures(){ get_state "consecutive_failures" "0"; }
get_execution_mode()      { get_state "execution_mode" "normal"; }

is_eco_mode() {
    [[ "$(get_execution_mode)" == "eco" ]]
}

is_bug_council_active() {
    [[ "$(get_state bug_council_activated)" == "TRUE" ]]
}

set_phase() {
    local phase="$1"
    set_state "current_phase" "$phase"
}

set_current_agent() {
    local agent="$1"
    [[ -z "$agent" ]] && { log_error "Agent name cannot be empty"; return 1; }
    set_state "current_agent" "$agent"
}

set_current_model() {
    local model="$1"
    set_state "current_model" "$model"
}

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

# Read circuit breaker state from state/circuit-breaker.md
get_circuit_breaker_state() {
    cat "${STATE_DIR}/circuit-breaker.md" 2>/dev/null | \
        awk '/^state:/ {sub(/^state: */, ""); sub(/ *$/, ""); print; exit}'
}

set_circuit_breaker_state() {
    local new_state="$1"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local file="${STATE_DIR}/circuit-breaker.md"
    local lockpath="${file}.lock"
    acquire_lock "$lockpath" || return 1
    trap "release_lock '$lockpath'" RETURN
    if grep -q "^state:" "$file"; then
        sed -i.bak "s|^state:.*|state: ${new_state}|" "$file"
        rm -f "${file}.bak"
    fi
    if [[ "$new_state" == "open" ]]; then
        if ! grep -q "^opened_at:" "$file"; then
            sed -i.bak "/^---$/a opened_at: ~" "$file"
            rm -f "${file}.bak"
        fi
        sed -i.bak "s|^opened_at:.*|opened_at: ${now}|" "$file"
        rm -f "${file}.bak"
    elif [[ "$new_state" == "half-open" ]]; then
        sed -i.bak "s|^half_open_at:.*|half_open_at: ${now}|" "$file"
        rm -f "${file}.bak"
    fi
    release_lock "$lockpath"
    trap - RETURN
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

# Tier order: haiku < sonnet < opus
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
                echo "opus"  # Already at top
            fi
            return
        fi
    done
    echo "sonnet"  # Default fallback
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

    # Compute cost (rough estimates; configurable in config.yaml)
    local input_rate="${INPUT_TOKEN_RATE_CENTS:-3}"   # $0.003 per 1k tokens
    local output_rate="${OUTPUT_TOKEN_RATE_CENTS:-15}"  # $0.015 per 1k tokens
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
# SESSION SUMMARY (read-only aggregations)
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
Tokens in:   $(get_frontmatter_value "$file" "total_tokens_input")
Tokens out:  $(get_frontmatter_value "$file" "total_tokens_output")
Cost (cents): $(get_frontmatter_value "$file" "total_cost_cents")
Cost (\$):    $(get_total_cost_dollars)
EOF
}

# Aggregate model usage from agent-runs/ files
get_model_usage() {
    local usage_file="${STATE_DIR}/model-usage.txt"
    > "$usage_file"  # truncate

    if [[ -d "$AGENT_RUNS_DIR" ]]; then
        for f in "$AGENT_RUNS_DIR"/*.md; do
            [[ -f "$f" ]] || continue
            local model
            model=$(get_frontmatter_value "$f" "model")
            local cost
            cost=$(get_frontmatter_value "$f" "cost_cents")
            echo "$model $cost" >> "$usage_file"
        done
    fi

    awk '{ usage[$1] += $2 } END { for (m in usage) printf "%-10s %d cents\n", m, usage[m] }' "$usage_file"
}

# ============================================================================
# SESSION ABORT
# ============================================================================

abort_session() {
    local reason="${1:-user_abort}"
    end_session "aborted" "$reason"
    log_info "Session aborted: $reason"
}

# ============================================================================
# ITERATION LIMITS
# ============================================================================

is_max_iterations_reached() {
    local current
    current=$(get_current_iteration)
    local max
    max=$(get_state "max_iterations" "10")
    [[ "$current" -ge "$max" ]]
}
