#!/bin/bash
# DevTeam Event Logging Functions (v6.2 — file-based, no SQLite)
# Provides secure event logging for DevTeam hooks and commands
#
# Usage: source this file in hooks and commands
#   source "$(dirname "$0")/../scripts/events.sh"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
# state.sh is sourced for shared lock primitives + session accessors.
source "${SCRIPT_DIR}/state.sh"

# ============================================================================
# PATH CONSTANTS
# ============================================================================

ROOT="${ROOT:-$(pwd)}"
STATE_DIR="${ROOT}/.devteam/state"
EVENTS_DIR="${STATE_DIR}/events"
GATES_DIR="${STATE_DIR}/gates.md"
AGENT_RUNS_DIR="${STATE_DIR}/agent-runs"

# ============================================================================
# VALID EVENT TYPES AND CATEGORIES
# ============================================================================

readonly VALID_EVENT_TYPES=(
    "session_started" "session_ended" "phase_changed"
    "agent_started" "agent_completed" "agent_failed"
    "model_escalated" "model_deescalated"
    "gate_passed" "gate_failed"
    "bug_council_activated" "bug_council_completed"
    "interview_started" "interview_question" "interview_completed"
    "research_started" "research_finding" "research_completed"
    "task_started" "task_completed" "task_failed"
    "error_occurred" "warning_issued"
    "abandonment_detected" "abandonment_prevented"
)

readonly VALID_EVENT_CATEGORIES=(
    "general" "session" "phase" "agent" "escalation"
    "gate" "bug_council" "interview" "research" "task"
    "error" "warning" "persistence"
)

# ============================================================================
# VALIDATION HELPERS
# ============================================================================

validate_event_type() {
    local event_type="$1"
    if ! _in_array "$event_type" "${VALID_EVENT_TYPES[@]}"; then
        log_warn "Unknown event type: $event_type (allowing anyway)" "events"; fi
    return 0
}

validate_event_category() {
    local category="$1"
    if ! _in_array "$category" "${VALID_EVENT_CATEGORIES[@]}"; then
        log_warn "Unknown event category: $category (allowing anyway)" "events"; fi
    return 0
}

# ============================================================================
# ATOMIC FILE HELPERS (H8/H9 fix: delegated to state.sh)
# ============================================================================
# events.sh uses state.sh's lock primitives — single mkdir + brief retry,
# and traps cover RETURN/ERR/INT/TERM so we never leak lock dirs on error.

_atomic_append() {
    atomic_append "$1" "$2"
}

_atomic_write() {
    atomic_write "$1" "$2"
}

# ============================================================================
# SESSION ACCESSORS — provided by state.sh; no duplicates here.
# (state.sh is sourced at the top of this file.)
# ============================================================================

# ============================================================================
# CORE EVENT LOGGING
# ============================================================================

# Log an event to events/<date>-events.md
# Args: event_type, [category], [message], [data], [agent], [model], [tokens_input], [tokens_output]
log_event() {
    local event_type="$1"
    local category="${2:-general}"
    local message="${3:-}"
    local data="${4:-}"
    local agent="${5:-}"
    local model="${6:-}"
    local tokens_input="${7:-0}"
    local tokens_output="${8:-0}"

    local session_id; session_id=$(get_current_session_id)
    if [[ -z "$session_id" ]]; then
        log_debug "No active session, skipping event log" "events"; return 0; fi

    if ! validate_numeric "$tokens_input" "tokens_input"; then tokens_input=0; fi
    if ! validate_numeric "$tokens_output" "tokens_output"; then tokens_output=0; fi

    local iteration; iteration=$(get_current_iteration) || iteration=0
    local phase; phase=$(get_current_phase) || phase=""
    local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local today; today=$(date +%Y-%m-%d)
    local events_file="${EVENTS_DIR}/${today}-events.md"

    mkdir -p "$EVENTS_DIR"
    [[ ! -f "$events_file" ]] && _atomic_write "$events_file" "# Events ${today}"

    local entry="## ${now} — ${event_type}
- session_id: ${session_id}
- category: ${category}
- message: ${message}"
    [[ -n "$agent" ]]       && entry+="
- agent: ${agent}"
    [[ -n "$model" ]]       && entry+="
- model: ${model}"
    [[ -n "$iteration" ]]   && entry+="
- iteration: ${iteration}"
    [[ -n "$phase" ]]       && entry+="
- phase: ${phase}"
    [[ -n "$data" ]]        && entry+="
- data: ${data}"
    [[ "$tokens_input" -gt 0 ]]  && entry+="
- tokens_input: ${tokens_input}"
    [[ "$tokens_output" -gt 0 ]] && entry+="
- tokens_output: ${tokens_output}"

    _atomic_append "$events_file" "$entry"
    log_debug "Event logged: $event_type" "events"
}

# ============================================================================
# SESSION EVENTS
# ============================================================================

log_session_started() {
    local command="$1"
    local command_type="$2"
    log_event "session_started" "session" "Session started: $command" \
        "$(json_object "command_type" "$command_type")"
}

log_session_ended() {
    local status="$1"
    local reason="$2"
    log_event "session_ended" "session" "Session ended: $status" \
        "$(json_object "status" "$status" "reason" "$reason")"
}

# ============================================================================
# PHASE EVENTS
# ============================================================================

log_phase_changed() {
    local new_phase="$1"
    local previous_phase="${2:-}"
    log_event "phase_changed" "phase" "Phase: $new_phase" \
        "$(json_object "previous" "$previous_phase" "current" "$new_phase")"
}

# ============================================================================
# AGENT EVENTS
# ============================================================================

log_agent_started() {
    local agent="$1"
    local model="$2"
    local task_id="${3:-}"

    if [[ -z "$agent" ]]; then log_error "Agent name required" "events"; return 1; fi

    local json_data; json_data=$(json_object "task_id" "$task_id")
    log_event "agent_started" "agent" "Agent started: $agent ($model)" \
        "$json_data" "$agent" "$model"

    # Create agent-run file
    local session_id; session_id=$(get_current_session_id)
    [[ -z "$session_id" ]] && return 0
    local iteration; iteration=$(get_current_iteration) || iteration=0
    local run_id; run_id=$(generate_id "run")
    local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    mkdir -p "$AGENT_RUNS_DIR"
    local body="---
run_id: ${run_id}
session_id: ${session_id}
agent: ${agent}
model: ${model}
started_at: ${now}
ended_at: ~
duration_seconds: ~
status: running
iteration: ${iteration}
task_id: ${task_id}
files_changed: []
tokens_input: 0
tokens_output: 0
cost_cents: 0
error_message: ~
---

# Agent run: ${agent}
"
    _atomic_write "${AGENT_RUNS_DIR}/${run_id}.md" "$body"
}

log_agent_completed() {
    local agent="$1"
    local model="$2"
    local files_changed="${3:-[]}"
    local tokens_input="${4:-0}"
    local tokens_output="${5:-0}"
    local cost_cents="${6:-0}"

    if [[ -z "$agent" ]]; then log_error "Agent name required" "events"; return 1; fi

    if ! validate_numeric "$tokens_input" "tokens_input";  then tokens_input=0; fi
    if ! validate_numeric "$tokens_output" "tokens_output"; then tokens_output=0; fi
    if ! validate_decimal "$cost_cents" "cost_cents";     then cost_cents=0; fi

    log_event "agent_completed" "agent" "Agent completed: $agent" \
        "$(json_object "files_changed" "$files_changed")" \
        "$agent" "$model" "$tokens_input" "$tokens_output"

    # Update most recent running agent-run for this session
    local session_id; session_id=$(get_current_session_id)
    [[ -z "$session_id" ]] && return 0
    local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [[ -d "$AGENT_RUNS_DIR" ]]; then
        local latest_run
        latest_run=$(ls -t "$AGENT_RUNS_DIR"/${session_id}-*.md 2>/dev/null | head -1 || true)
        [[ -z "$latest_run" ]] && latest_run=$(ls -t "$AGENT_RUNS_DIR"/*.md 2>/dev/null | head -1 || true)
        if [[ -n "$latest_run" ]] && grep -q "^status: running" "$latest_run" 2>/dev/null; then
            local ended_at; ended_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
            local started_str; started_str=$(awk '/^started_at:/ {sub(/^started_at: */,""); print}' "$latest_run" 2>/dev/null || echo '')
            local started_epoch; started_epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$started_str" +%s 2>/dev/null || echo 0)
            local now_epoch; now_epoch=$(date +%s)
            local duration=$((now_epoch - started_epoch))
            sed -i.bak \
                -e "s|^status: running|status: success|" \
                -e "s|^ended_at:.*|ended_at: ${now}|" \
                -e "s|^duration_seconds:.*|duration_seconds: ${duration}|" \
                -e "s|^tokens_input:.*|tokens_input: ${tokens_input}|" \
                -e "s|^tokens_output:.*|tokens_output: ${tokens_output}|" \
                -e "s|^cost_cents:.*|cost_cents: ${cost_cents}|" \
                "$latest_run" 2>/dev/null || true
            rm -f "${latest_run}.bak"
        fi
    fi
}

log_agent_failed() {
    local agent="$1"
    local model="$2"
    local error_message="$3"
    local error_type="${4:-unknown}"

    if [[ -z "$agent" ]]; then log_error "Agent name required" "events"; return 1; fi

    log_event "agent_failed" "agent" "Agent failed: $agent - $error_message" \
        "$(json_object "error_type" "$error_type")" "$agent" "$model"

    increment_failures

    # Update most recent running agent-run for this session
    local session_id; session_id=$(get_current_session_id)
    [[ -z "$session_id" ]] && return 0
    local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [[ -d "$AGENT_RUNS_DIR" ]]; then
        local latest_run
        latest_run=$(ls -t "$AGENT_RUNS_DIR"/*.md 2>/dev/null | head -1 || true)
        if [[ -n "$latest_run" ]] && grep -q "^status: running" "$latest_run" 2>/dev/null; then
            sed -i.bak \
                -e "s|^status: running|status: failed|" \
                -e "s|^ended_at:.*|ended_at: ${now}|" \
                -e "s|^error_message:.*|error_message: ${error_message}|" \
                -e "s|^error_type:.*|error_type: ${error_type}|" \
                "$latest_run" 2>/dev/null || true
            rm -f "${latest_run}.bak"
        fi
    fi
}

# ============================================================================
# ESCALATION EVENTS
# ============================================================================

log_model_escalated() {
    local from_model="$1"
    local to_model="$2"
    local reason="$3"
    local agent="${4:-}"
    log_event "model_escalated" "escalation" \
        "Model escalated: $from_model -> $to_model ($reason)" \
        "$(json_object "from" "$from_model" "to" "$to_model" "reason" "$reason")" \
        "$agent" "$to_model"
}

log_model_deescalated() {
    local from_model="$1"
    local to_model="$2"
    local reason="$3"
    log_event "model_deescalated" "escalation" \
        "Model de-escalated: $from_model -> $to_model ($reason)" \
        "$(json_object "from" "$from_model" "to" "$to_model" "reason" "$reason")"
}

# ============================================================================
# QUALITY GATE EVENTS
# ============================================================================

log_gate_passed() {
    local gate="$1"
    local details="${2:-{}}"

    if [[ -z "$gate" ]]; then log_error "Gate name required" "events"; return 1; fi

    log_event "gate_passed" "gate" "Gate passed: $gate" "$details"

    local session_id; session_id=$(get_current_session_id)
    [[ -z "$session_id" ]] && return 0
    local iteration; iteration=$(get_current_iteration) || iteration=0
    local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    mkdir -p "$(dirname "$GATES_DIR")"
    [[ ! -f "$GATES_DIR" ]] && _atomic_write "$GATES_DIR" "# Quality Gates"
    _atomic_append "$GATES_DIR" "## ${now} — gate_passed: ${gate}
- session_id: ${session_id}
- iteration: ${iteration}
- status: pass
- gate: ${gate}
- details: ${details}"
}

log_gate_failed() {
    local gate="$1"
    local error_count="${2:-0}"
    local details="${3:-{}}"

    if [[ -z "$gate" ]]; then log_error "Gate name required" "events"; return 1; fi
    if ! validate_numeric "$error_count" "error_count"; then error_count=0; fi

    log_event "gate_failed" "gate" "Gate failed: $gate ($error_count errors)" "$details"

    local session_id; session_id=$(get_current_session_id)
    [[ -z "$session_id" ]] && return 0
    local iteration; iteration=$(get_current_iteration) || iteration=0
    local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    mkdir -p "$(dirname "$GATES_DIR")"
    [[ ! -f "$GATES_DIR" ]] && _atomic_write "$GATES_DIR" "# Quality Gates"
    _atomic_append "$GATES_DIR" "## ${now} — gate_failed: ${gate}
- session_id: ${session_id}
- iteration: ${iteration}
- status: fail
- gate: ${gate}
- error_count: ${error_count}
- details: ${details}"
}

# ============================================================================
# BUG COUNCIL EVENTS
# ============================================================================

log_bug_council_activated() {
    local reason="$1"
    if [[ -z "$reason" ]]; then log_error "Reason required" "events"; return 1; fi
    log_event "bug_council_activated" "bug_council" \
        "Bug Council activated: $reason" \
        "$(json_object "reason" "$reason")"
}

log_bug_council_completed() {
    local winning_proposal="$1"
    local votes="${2:-{}}"
    log_event "bug_council_completed" "bug_council" \
        "Bug Council decision: $winning_proposal" "$votes"
}

# ============================================================================
# INTERVIEW EVENTS
# ============================================================================

log_interview_started() {
    local interview_type="$1"
    if [[ -z "$interview_type" ]]; then log_error "Interview type required" "events"; return 1; fi
    log_event "interview_started" "interview" \
        "Interview started: $interview_type" \
        "$(json_object "type" "$interview_type")"
}

log_interview_question() {
    local question_key="$1"
    local question_text="$2"
    local response="${3:-}"
    log_event "interview_question" "interview" "Q: $question_text" \
        "$(json_object "key" "$question_key" "response" "$response")"
}

log_interview_completed() {
    local questions_count="$1"
    if ! validate_numeric "$questions_count" "questions_count"; then questions_count=0; fi
    log_event "interview_completed" "interview" \
        "Interview completed ($questions_count questions)" \
        "$(json_object "questions_count" "$questions_count")"
}

# ============================================================================
# RESEARCH EVENTS
# ============================================================================

log_research_started() {
    log_event "research_started" "research" "Research phase started"
}

log_research_finding() {
    local finding_type="$1"
    local title="$2"
    local description="${3:-}"
    local priority="${4:-medium}"

    if [[ -z "$finding_type" ]] || [[ -z "$title" ]]; then
        log_error "Finding type and title required" "events"; return 1; fi

    log_event "research_finding" "research" "Finding: $title" \
        "$(json_object "type" "$finding_type" "priority" "$priority" "description" "$description")"
}

log_research_completed() {
    local findings_count="$1"
    local blockers_count="${2:-0}"

    if ! validate_numeric "$findings_count" "findings_count";  then findings_count=0; fi
    if ! validate_numeric "$blockers_count" "blockers_count"; then blockers_count=0; fi

    log_event "research_completed" "research" \
        "Research completed ($findings_count findings, $blockers_count blockers)" \
        "$(json_object "findings" "$findings_count" "blockers" "$blockers_count")"
}

# ============================================================================
# TASK EVENTS
# ============================================================================

log_task_started() {
    local task_id="$1"
    local task_description="$2"
    if [[ -z "$task_id" ]]; then log_error "Task ID required" "events"; return 1; fi
    log_event "task_started" "task" "Task started: $task_id - $task_description" \
        "$(json_object "task_id" "$task_id")"
}

log_task_completed() {
    local task_id="$1"
    if [[ -z "$task_id" ]]; then log_error "Task ID required" "events"; return 1; fi
    log_event "task_completed" "task" "Task completed: $task_id" \
        "$(json_object "task_id" "$task_id")"
}

log_task_failed() {
    local task_id="$1"
    local reason="$2"
    if [[ -z "$task_id" ]]; then log_error "Task ID required" "events"; return 1; fi
    log_event "task_failed" "task" "Task failed: $task_id - $reason" \
        "$(json_object "task_id" "$task_id" "reason" "$reason")"
}

# ============================================================================
# ERROR AND WARNING EVENTS
# ============================================================================

log_error_event() {
    local message="$1"
    local details="${2:-{}}"
    log_event "error_occurred" "error" "$message" "$details"
}

log_warning_event() {
    local message="$1"
    local details="${2:-{}}"
    log_event "warning_issued" "warning" "$message" "$details"
}

# ============================================================================
# ABANDONMENT EVENTS
# ============================================================================

log_abandonment_detected() {
    local pattern="$1"
    local attempt_number="$2"
    if ! validate_numeric "$attempt_number" "attempt_number"; then attempt_number=0; fi
    log_event "abandonment_detected" "persistence" \
        "Abandonment pattern detected: $pattern (attempt $attempt_number)" \
        "$(json_object "pattern" "$pattern" "attempt" "$attempt_number")"
}

log_abandonment_prevented() {
    local action="$1"
    log_event "abandonment_prevented" "persistence" \
        "Abandonment prevented: $action" "$(json_object "action" "$action")"
}

# ============================================================================
# QUERY FUNCTIONS (file-based)
# ============================================================================

get_recent_events() {
    local limit="${1:-20}"
    local session_id="${2:-}"
    if ! validate_numeric "$limit" "limit"; then limit=20; fi
    if [[ -z "$session_id" ]]; then session_id=$(get_current_session_id); fi
    [[ -z "$session_id" ]] && return 0
    if ! validate_session_id "$session_id"; then return 1; fi

    local today; today=$(date +%Y-%m-%d)
    local events_file="${EVENTS_DIR}/${today}-events.md"
    [[ -f "$events_file" ]] || return 0

    # L8 fix: use tail on the file (single block read) and filter for the
    # current session, instead of grepping the entire daily log.
    tail -n 5000 "$events_file" 2>/dev/null \
        | awk -v sid="$session_id" '
            /^## / { rec = $0; in_session = 0 }
            /^- session_id: / { if ($0 ~ sid) in_session = 1; print rec; next }
            in_session { print }
        ' \
        | tail -n $((limit * 12))
}

get_events_by_type() {
    local event_type="$1"
    local session_id="${2:-}"
    if [[ -z "$event_type" ]]; then log_error "Event type required" "events"; return 1; fi
    if [[ -z "$session_id" ]]; then session_id=$(get_current_session_id); fi
    [[ -z "$session_id" ]] && echo "[]" && return 0
    if ! validate_session_id "$session_id"; then echo "[]"; return 1; fi

    local today; today=$(date +%Y-%m-%d)
    local events_file="${EVENTS_DIR}/${today}-events.md"
    if [[ -f "$events_file" ]]; then
        grep -B 1 -A 8 "^## .*— ${event_type}" "$events_file" 2>/dev/null
    fi
}

get_gate_results() {
    local session_id="${1:-}"
    if [[ -z "$session_id" ]]; then session_id=$(get_current_session_id); fi
    [[ -z "$session_id" ]] && return 0
    if ! validate_session_id "$session_id"; then return 1; fi

    if [[ -f "$GATES_DIR" ]]; then
        grep -B 1 -A 6 "session_id: ${session_id}" "$GATES_DIR" 2>/dev/null
    fi
}

get_escalation_history() {
    local session_id="${1:-}"
    if [[ -z "$session_id" ]]; then session_id=$(get_current_session_id); fi
    [[ -z "$session_id" ]] && return 0
    if ! validate_session_id "$session_id"; then return 1; fi

    local today; today=$(date +%Y-%m-%d)
    local events_file="${EVENTS_DIR}/${today}-events.md"
    if [[ -f "$events_file" ]]; then
        grep -B 1 -A 5 "^## .*— model_escalated" "$events_file" 2>/dev/null
    fi
}

# ============================================================================
# INITIALIZATION
# ============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    setup_error_trap
fi
