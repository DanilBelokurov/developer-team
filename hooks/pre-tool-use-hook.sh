#!/bin/bash
# DevTeam Pre-Tool-Use Hook (v6.5 — file-based)
# Runs BEFORE each tool call to validate and inject context.
#
# Exit codes:
#   0 = Allow tool call
#   2 = Block tool call with message
#
# Environment variables expected:
#   CLAUDE_TOOL_NAME  — name of the tool being called
#   CLAUDE_TOOL_INPUT — JSON input for the tool

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/lib/hook-common.sh" ]]; then
    source "$SCRIPT_DIR/lib/hook-common.sh"
elif [[ -f "$SCRIPT_DIR/../lib/hook-common.sh" ]]; then
    source "$SCRIPT_DIR/../lib/hook-common.sh"
else
    echo "[pre-tool-use] Warning: hook-common.sh not found" >&2
    exit 0
fi

init_hook "pre-tool-use"
prime_hot_cache

# ============================================================================
# CONFIGURATION
# ============================================================================

TOOL_NAME="${CLAUDE_TOOL_NAME:-}"
TOOL_INPUT="${CLAUDE_TOOL_INPUT:-}"

if [[ -z "$TOOL_NAME" ]] && [[ -z "$TOOL_INPUT" ]]; then
    log_warn "pre-tool-use" "No CLAUDE_TOOL_NAME or CLAUDE_TOOL_INPUT set"
    exit 0
fi

# ============================================================================
# DANGEROUS COMMAND PATTERNS
# ============================================================================
# M5 fix: patterns are anchored with word boundaries / start-end anchors so
# they don't match code that *mentions* the strings (regex testers, docs).
# Bash-side filtering is done by an awk pass over the command, not by
# piping through grep.

DANGEROUS_PATTERNS=(
    # Destructive file operations — exact-leading match
    '^rm[[:space:]]+-rf[[:space:]]+/( |$|\*)'
    '^rm[[:space:]]+-rf[[:space:]]+~(/|$)'
    '^rm[[:space:]]+-rf[[:space:]]+\$HOME(/|$)'

    # Disk/system destruction
    '^dd[[:space:]]+if=/dev/(zero|random)'
    '^mkfs\.'
    '^fdisk[[:space:]]'
    '^parted[[:space:]]'
    '>[[:space:]]*/dev/sd'
    '>[[:space:]]*/dev/nvme'

    # Fork bombs
    '^:[[:space:]]*\(\)[[:space:]]*\{[[:space:]]*:\|:&[[:space:]]*\};'
    '^:[[:space:]]*\(\)\{[[:space:]]*:\|:&[[:space:]]*\};'

    # Dangerous permissions
    '^chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/'
    '^chown[[:space:]]+-R.*[[:space:]]+/'

    # Git force push to protected branches
    '^git[[:space:]]+push.*--force.*[[:space:]](main|master)( |$)'
    '^git[[:space:]]+push.*-f.*[[:space:]](main|master)( |$)'

    # Database destruction (whole-statement)
    '^[[:space:]]*DROP[[:space:]]+(DATABASE|TABLE)'
    '^[[:space:]]*TRUNCATE[[:space:]]+TABLE'
    'DELETE[[:space:]]+FROM[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]+WHERE[[:space:]]+1[[:space:]]*(;|$)'

    # Credential/key exposure — only matches actual cat to those paths
    '^cat[[:space:]]+[^|;&]*\.ssh/id_'
    '^cat[[:space:]]+[^|;&]*/etc/shadow'
    '^cat[[:space:]]+[^|;&]*/etc/passwd'

    # Crypto mining / pipe-to-shell
    '^curl[[:space:]]+[^|]*\|[[:space:]]*(bash|sh)( |$)'
    '^wget[[:space:]]+[^|]*\|[[:space:]]*(bash|sh)( |$)'

    # Arbitrary code execution — bare `eval $var`, not mentions of "eval"
    '^eval[[:space:]]+\$'
    '^eval[[:space:]]+[^"'\''[:space:]]'

    # Privilege escalation — bare `sudo command`, not `echo "sudo"`
    '^sudo[[:space:]]+[^#]'

    # World-writable chmod on root
    '^chmod[[:space:]]+777[[:space:]]+/'
)

# Pre-compile patterns into a single awk script (built once).
_dangerous_patterns_awk() {
    local i=0
    local awk_script=""
    for pattern in "${DANGEROUS_PATTERNS[@]}"; do
        if [[ $i -gt 0 ]]; then
            awk_script+=" || "
        fi
        # awk's match() with regex. Escape the pattern for awk string syntax.
        local escaped="${pattern//\\/\\\\}"
        escaped="${escaped//\"/\\\"}"
        awk_script+="match(\$0, /${escaped}/)"
        i=$((i + 1))
    done
    echo "$awk_script"
}

# ============================================================================
# SCOPE VALIDATION FOR FILE OPERATIONS (H3 fix)
# ============================================================================
# Single jq pass to extract file_path / command from the input, instead
# of multiple sed/grep invocations per tool type.

# Pre-parse the input once. Sets: _PARSED_FILE_PATH, _PARSED_COMMAND.
_parse_tool_input() {
    _PARSED_FILE_PATH=""
    _PARSED_COMMAND=""
    [[ -z "$TOOL_INPUT" ]] && return 0

    if command -v jq &>/dev/null; then
        # Cap input size to avoid huge-compiler-output blowups.
        local capped="${TOOL_INPUT:0:50000}"
        case "$TOOL_NAME" in
            Write|Edit|NotebookEdit)
                _PARSED_FILE_PATH=$(printf '%s' "$capped" | jq -r '.file_path // .notebook_path // empty' 2>/dev/null)
                ;;
            Bash)
                _PARSED_COMMAND=$(printf '%s' "$capped" | jq -r '.command // empty' 2>/dev/null)
                # Only extract a file_path if the command redirects to one.
                if [[ "$_PARSED_COMMAND" =~ [[:space:]]*\>[[:space:]]*([^[:space:];&|]+) ]] \
                    || [[ "$_PARSED_COMMAND" =~ [[:space:]]+(sed[[:space:]]+-i|mv|cp)[[:space:]]+([^[:space:];&|]+) ]]; then
                    _PARSED_FILE_PATH="${BASH_REMATCH[1]:-${BASH_REMATCH[2]}}"
                fi
                ;;
            Task)
                _PARSED_FILE_PATH=""  # Task uses prompt, not file
                ;;
        esac
    else
        # No jq — fall back to simple sed extraction, but only once.
        case "$TOOL_NAME" in
            Write|Edit|NotebookEdit)
                _PARSED_FILE_PATH=$(printf '%s' "${TOOL_INPUT:0:50000}" \
                    | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
                ;;
            Bash)
                _PARSED_COMMAND=$(printf '%s' "${TOOL_INPUT:0:50000}" \
                    | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
                ;;
        esac
    fi
}

validate_file_operation() {
    _parse_tool_input
    local file_path="$_PARSED_FILE_PATH"
    [[ -n "$file_path" ]] || return 0

    # Strip stray quotes that sometimes appear in parsed values.
    file_path="${file_path%\"}"
    file_path="${file_path#\"}"

    if ! file_in_scope "$file_path"; then
        log_warn "pre-tool-use" "Scope violation attempted: $file_path"
        log_event_to_db "scope_violation" "warning" "Attempted to modify out-of-scope file: $file_path"

        local scope_list
        scope_list=$(get_scope_files | head -10)

        inject_system_message "scope-warning" "
SCOPE VIOLATION BLOCKED

You attempted to modify: $file_path

This file is outside your allowed scope for this task.

Allowed scope:
$scope_list

Please only modify files within the allowed scope.
"
        exit 2
    fi
}

# ============================================================================
# DANGEROUS COMMAND DETECTION (H3 + M5 fix)
# ============================================================================

check_dangerous_commands() {
    [[ "$TOOL_NAME" == "Bash" ]] || return 0

    _parse_tool_input
    local command="$_PARSED_COMMAND"
    [[ -n "$command" ]] || return 0

    local matched=""
    local awk_script
    awk_script=$(_dangerous_patterns_awk)

    # awk-based pattern matching: a single pass over the command, with all
    # 30+ dangerous patterns evaluated at once. Returns the matching pattern.
    matched=$(printf '%s\n' "$command" | awk -v script="$awk_script" '
        { if (eval("" script "")) { print "matched"; exit } }
    ')

    if [[ "$matched" == "matched" ]]; then
        log_error "pre-tool-use" "Dangerous command blocked"
        log_event_to_db "dangerous_command" "error" "Blocked dangerous Bash command"

        inject_system_message "danger-blocked" "
DANGEROUS COMMAND BLOCKED

The command you attempted contains a potentially destructive pattern.

If this is intentional and authorized:
1. Ask the user for explicit confirmation
2. Explain why this destructive operation is necessary
3. The user can override with explicit approval
"
        exit 2
    fi
}

# ============================================================================
# ITERATION WARNING INJECTION (M1 fix: uses cached values)
# ============================================================================

inject_iteration_context() {
    local iteration max remaining
    iteration=$(get_current_iteration)
    max=$(cache_get max_iter)
    [[ -z "$max" ]] && max=$(get_state "max_iterations" "$MAX_ITERATIONS")
    [[ "$iteration" =~ ^[0-9]+$ ]] || iteration=0
    [[ "$max" =~ ^[0-9]+$ ]] || max=100
    remaining=$((max - iteration))

    if [[ "$remaining" -le 5 ]] && [[ "$remaining" -gt 0 ]]; then
        inject_system_message "iteration-warning" "
ITERATION WARNING

You have $remaining iterations remaining (current: $iteration/$max).

Focus on:
1. Fixing the most critical issues first
2. Running quality gates to verify progress
3. Saving checkpoints if needed

If you cannot complete within remaining iterations, prioritize a stable state.
"
    elif [[ "$remaining" -le 0 ]]; then
        inject_system_message "iteration-limit" "
ITERATION LIMIT REACHED

You have reached the maximum iteration count ($max).

Ensure you:
1. Save any important progress
2. Document current state
3. Report what was completed vs remaining

Use EXIT_SIGNAL: true to cleanly end the session.
"
    fi
}

# ============================================================================
# CIRCUIT BREAKER CHECK (M1 fix: uses cached failures)
# ============================================================================

check_circuit_breaker() {
    local failures max_fail warning_threshold
    failures=$(get_consecutive_failures)
    [[ "$failures" =~ ^[0-9]+$ ]] || failures=0
    max_fail="$MAX_FAILURES"
    [[ "$max_fail" =~ ^[0-9]+$ ]] || max_fail=5
    warning_threshold=$((max_fail - 2))

    if [[ "$failures" -ge "$warning_threshold" ]] && [[ "$failures" -lt "$max_fail" ]]; then
        inject_system_message "failure-warning" "
FAILURE WARNING

Consecutive failures: $failures / $max_fail

The circuit breaker will trip after $max_fail consecutive failures,
requiring human intervention.

Consider:
1. Trying a different approach
2. Breaking the problem into smaller steps
3. Escalating to a more capable model
4. Asking for help with specific blockers
"
    fi
}

# ============================================================================
# TOOL-SPECIFIC VALIDATION (H3 fix: single-pass jq)
# ============================================================================

validate_tool_specific() {
    [[ "$TOOL_NAME" == "Task" ]] || return 0

    local prompt="${_PARSED_COMMAND:-}"  # _parse_tool_input sets command for Bash; for Task we read prompt
    if [[ -z "$prompt" ]] && command -v jq &>/dev/null && [[ -n "$TOOL_INPUT" ]]; then
        prompt=$(printf '%s' "${TOOL_INPUT:0:50000}" | jq -r '.prompt // empty' 2>/dev/null)
    fi
    if [[ -z "$prompt" ]] || [[ ${#prompt} -lt 10 ]]; then
        log_warn "pre-tool-use" "Task tool called with insufficient prompt"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    if [[ -z "$TOOL_NAME" ]]; then
        exit 0
    fi

    log_debug "pre-tool-use" "Validating tool: $TOOL_NAME"

    # Most expensive → least expensive ordering.
    check_dangerous_commands
    validate_file_operation
    validate_tool_specific
    check_circuit_breaker
    inject_iteration_context

    mcp_notify "pre_tool_use" "$(get_claude_context)"
    exit 0
}

main "$@"