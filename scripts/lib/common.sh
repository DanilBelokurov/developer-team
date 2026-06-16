#!/bin/bash
# DevTeam Common Library
# Shared utilities for logging, validation, and general-purpose helpers
# v6.2 — no SQLite dependency

set -euo pipefail

# Idempotency guard — skip if already sourced
if [ -n "${_COMMON_SH_SOURCED:-}" ]; then return 0; fi
_COMMON_SH_SOURCED=1

# ============================================================================
# LOGGING
# ============================================================================

LOG_LEVEL="${DEVTEAM_LOG_LEVEL:-info}"

readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_NC='\033[0m'

# Convert log level name to numeric priority (bash 3.x compatible — no associative arrays)
_log_level_to_num() {
    local level="$1"
    case "$level" in
        debug) echo 0 ;;
        info)  echo 1 ;;
        warn)  echo 2 ;;
        error) echo 3 ;;
        *)     echo 1 ;;
    esac
}

_should_log() {
    local level="$1"
    local current_num
    local msg_num
    current_num=$(_log_level_to_num "$LOG_LEVEL")
    msg_num=$(_log_level_to_num "$level")
    [ "$msg_num" -ge "$current_num" ]
}

log() {
    local level="$1"
    local message="$2"
    local context="${3:-}"
    if ! _should_log "$level"; then return 0; fi
    local color=""
    case "$level" in
        debug) color="$COLOR_BLUE" ;;
        info)  color="$COLOR_GREEN" ;;
        warn)  color="$COLOR_YELLOW" ;;
        error) color="$COLOR_RED" ;;
    esac
    local ctx_str=""
    if [ -n "$context" ]; then ctx_str=" [$context]"; fi
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [devteam] [$level]${ctx_str}${COLOR_NC} $message" >&2
}

log_debug() { log "debug" "$1" "${2:-}"; }
log_info()  { log "info" "$1" "${2:-}"; }
log_warn()  { log "warn" "$1" "${2:-}"; }
log_error() { log "error" "$1" "${2:-}"; }

# ============================================================================
# INPUT VALIDATION
# ============================================================================

readonly VALID_SESSION_FIELDS=(
    "status" "current_phase" "current_agent" "current_model"
    "current_iteration" "consecutive_failures" "execution_mode"
    "bug_council_activated" "bug_council_reason" "circuit_breaker_state"
    "max_consecutive_failures" "max_iterations" "plan_id" "sprint_id"
    "exit_reason" "ended_at" "total_tokens_input" "total_tokens_output"
    "total_cost_cents"
)

readonly VALID_PHASES=(
    "initializing" "interview" "research" "planning" "executing"
    "quality_check" "bug_council" "completed" "aborted" "failed"
)

readonly VALID_MODELS=("haiku" "sonnet" "opus" "bug_council")

readonly VALID_STATUSES=("running" "completed" "aborted" "failed")

_in_array() {
    local needle="$1"; shift
    for item in "$@"; do
        if [ "$item" = "$needle" ]; then return 0; fi
    done; return 1
}

validate_field_name() {
    local field="$1"
    if ! _in_array "$field" "${VALID_SESSION_FIELDS[@]}"; then
        log_error "Invalid field name: $field" "validation"; return 1; fi
    return 0
}

validate_phase() {
    local phase="$1"
    if ! _in_array "$phase" "${VALID_PHASES[@]}"; then
        log_error "Invalid phase: $phase" "validation"; return 1; fi
    return 0
}

validate_model() {
    local model="$1"
    if ! _in_array "$model" "${VALID_MODELS[@]}"; then
        log_error "Invalid model: $model" "validation"; return 1; fi
    return 0
}

validate_status() {
    local status="$1"
    if ! _in_array "$status" "${VALID_STATUSES[@]}"; then
        log_error "Invalid status: $status" "validation"; return 1; fi
    return 0
}

validate_session_id() {
    local session_id="$1"
    if [[ ! "$session_id" =~ ^session-[0-9]{8}-[0-9]{6}-[a-f0-9]+$ ]]; then
        log_error "Invalid session ID format: $session_id" "validation"; return 1; fi
    return 0
}

validate_numeric() {
    local value="$1"
    local name="${2:-value}"
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        log_error "Invalid numeric $name: $value" "validation"; return 1; fi
    return 0
}

validate_decimal() {
    local value="$1"
    local name="${2:-value}"
    if [[ ! "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Invalid decimal $name: $value" "validation"; return 1; fi
    return 0
}

# ============================================================================
# ESCAPING
# ============================================================================

# Escape string for safe use in text files (newline-safe, single-quote-safe)
file_escape() {
    local value="$1"
    printf '%s' "$value"
}

# Escape string for safe JSON value
json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    echo "$value"
}

# Build a JSON object from key-value pairs
# Usage: json_object "key1" "value1" "key2" "value2" ...
json_object() {
    local result="{"
    local first=true
    while [ $# -ge 2 ]; do
        local key="$1" value="$2"; shift 2
        if [ "$first" = true ]; then first=false; else result+=", "; fi
        result+="\"$key\": \"$(json_escape "$value")\""
    done
    result+="}"
    echo "$result"
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

on_error() {
    local line_no="$1" error_code="$2"
    log_error "Error on line $line_no (exit code: $error_code)" "trap"
}

setup_error_trap() {
    trap 'on_error ${LINENO} $?' ERR
}

# ============================================================================
# UTILITIES
# ============================================================================

generate_id() {
    local prefix="${1:-id}"
    local hex_suffix
    if command -v xxd &>/dev/null; then
        hex_suffix=$(head -c 8 /dev/urandom | xxd -p)
    else
        hex_suffix=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
    fi
    echo "${prefix}-$(date +%Y%m%d-%H%M%S)-${hex_suffix}"
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command not found: $cmd" "setup"; return 1; fi
    return 0
}

ensure_git() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not a git repository" "git"; return 1; fi
    return 0
}

format_number() {
    local num="$1"
    if printf "%'d" "$num" 2>/dev/null; then return 0; fi
    echo "$num" | awk '{
        s = $0; len = length(s); result = ""
        for (i = 1; i <= len; i++) {
            if (i > 1 && (len - i + 1) % 3 == 0) result = result ","
            result = result substr(s, i, 1)
        }
        print result
    }'
}

file_size_bytes() {
    local filepath="$1"
    if [ ! -f "$filepath" ]; then echo "0"; return 1; fi
    wc -c < "$filepath" | tr -d ' '
}

validate_file_path() {
    local filepath="$1"
    local allowed_root="${2:-$(pwd)}"
    if [ -z "$filepath" ]; then
        log_error "Empty file path" "validation"; return 1; fi
    local resolved
    if command -v realpath &>/dev/null; then
        resolved=$(realpath -m "$allowed_root/$filepath" 2>/dev/null) || resolved=""
    elif readlink -f "/" &>/dev/null 2>&1; then
        resolved=$(readlink -f "$allowed_root/$filepath" 2>/dev/null) || resolved=""
    else
        if [[ "$filepath" == *".."* ]]; then
            log_error "Path traversal detected: $filepath" "validation"; return 1; fi
        resolved="$allowed_root/$filepath"
    fi
    if [ -z "$resolved" ]; then
        log_error "Cannot resolve path: $filepath" "validation"; return 1; fi
    return 0
}
