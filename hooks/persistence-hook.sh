#!/bin/bash
# DevTeam Persistence Hook (v6.5 — file-based, single-grep detection)
# Detects and prevents premature task abandonment.
#
# Exit codes:
#   0 = Allow (output is acceptable)
#   2 = Block and re-engage (detected abandonment attempt)
#
# Environment variables expected:
#   QWEN_OUTPUT — last assistant message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/lib/hook-common.sh" ]]; then
    source "$SCRIPT_DIR/lib/hook-common.sh"
elif [[ -f "$SCRIPT_DIR/../lib/hook-common.sh" ]]; then
    source "$SCRIPT_DIR/../lib/hook-common.sh"
else
    echo "[persistence] Warning: hook-common.sh not found" >&2
    exit 0
fi

init_hook "persistence"
prime_hot_cache

# ============================================================================
# CONFIGURATION
# ============================================================================

MESSAGE="${QWEN_OUTPUT:-}"
[[ -z "$MESSAGE" ]] && exit 0

# ============================================================================
# ABANDONMENT DETECTION PATTERNS
# ============================================================================

GIVE_UP_PATTERNS=(
    "I cannot complete this"
    "I'm unable to"
    "I can't figure out"
    "I don't know how to"
    "I'm not sure how to proceed"
    "I give up"
    "I'm stuck"
    "This is beyond my"
    "I cannot determine"
    "I'm at a loss"
    "I have no idea"
    "I've done what I can"
    "That's all I can do"
    "I've tried everything"
    "Nothing else I can try"
    "I'm out of ideas"
    "I've exhausted"
    "No other options"
    "You should try"
    "You might want to"
    "You'll need to manually"
    "This requires human"
    "A human needs to"
    "You could try"
    "Perhaps you could"
    "Maybe you should"
    "I'll stop here"
    "Let me stop"
    "I think we should stop"
    "We can stop here"
    "I'm going to stop"
    "That should be enough"
    "I'll leave it here"
    "This is too complex"
    "This would take too long"
    "I don't have access"
    "I can't access"
    "Outside my capabilities"
    "Beyond my ability"
    "Not possible for me"
    "I lack the ability"
)

PASSIVE_ABANDONMENT_PATTERNS=(
    "Let me know if you'd like"
    "You can try"
    "You might try"
    "would you like me to"
    "should I"
    "I can stop here"
    "we could stop"
    "that should work"
    "should be working"
    "Let me know if"
    "If you need anything else"
    "I'm here if you need"
)

PERMISSION_SEEKING_PATTERNS=(
    "Should I proceed"
    "Do you want me to"
    "Would you like me to"
    "Shall I"
    "Want me to"
    "Can I"
    "May I"
    "Is it okay if"
    "Would it be okay"
    "Do you mind if"
)

LEGITIMATE_STOP_PATTERNS=(
    "EXIT_SIGNAL: true"
    "EXIT_SIGNAL:true"
    "All tests passing"
    "All quality gates passed"
    "Task completed successfully"
    "Implementation complete"
    "Ready for review"
    "Committed and pushed"
    "All acceptance criteria met"
    "Successfully completed"
    "/devteam:end"
)

# ============================================================================
# COMPILED REGEX (H5 fix: 4 patterns × ~30 alternations each → 1 grep pass)
# ============================================================================
# We build one big case-insensitive regex per detection class, with all
# patterns alternated. grep -m1 returns at first hit. Bash-side we then
# identify *which* pattern matched by walking the original list once.

# Escape regex metacharacters for use inside an extended-regex alternation.
_re_escape() {
    printf '%s' "$1" | sed 's/[][(){}.*+?^$|\\]/\\&/g'
}

_build_combined_regex() {
    local -n arr=$1
    local first=1
    local out=""
    for p in "${arr[@]}"; do
        if [[ $first -eq 1 ]]; then
            out="$(_re_escape "$p")"
            first=0
        else
            out="${out}|$(_re_escape "$p")"
        fi
    done
    printf '%s' "$out"
}

LEGITIMATE_RE=$( _build_combined_regex LEGITIMATE_STOP_PATTERNS )
GIVE_UP_RE=$( _build_combined_regex GIVE_UP_PATTERNS )
PASSIVE_RE=$( _build_combined_regex PASSIVE_ABANDONMENT_PATTERNS )
PERMISSION_RE=$( _build_combined_regex PERMISSION_SEEKING_PATTERNS )

# ============================================================================
# DETECTION
# ============================================================================

# Find the first matching pattern in $1 (patterns from array $2).
# Returns: pattern text on stdout, empty if none.
find_first_match() {
    local message="$1"
    local -n patterns=$2
    for p in "${patterns[@]}"; do
        # Case-insensitive substring match.
        if [[ "${message,,}" == *"${p,,}"* ]]; then
            printf '%s' "$p"
            return 0
        fi
    done
    return 1
}

# Check legitimate completion first (allowed).
if grep -qiE "$LEGITIMATE_RE" <<< "$MESSAGE"; then
    log_info "persistence" "Legitimate completion detected"
    exit 0
fi

DETECTED_PATTERN=""
DETECTION_TYPE=""

# Direct abandonment
DETECTED_PATTERN=$(find_first_match "$MESSAGE" GIVE_UP_PATTERNS) \
    && DETECTION_TYPE="direct_abandonment"

# Passive abandonment
if [[ -z "$DETECTED_PATTERN" ]]; then
    DETECTED_PATTERN=$(find_first_match "$MESSAGE" PASSIVE_ABANDONMENT_PATTERNS) \
        && DETECTION_TYPE="passive_abandonment"
fi

# Permission seeking — only when there's an active task
if [[ -z "$DETECTED_PATTERN" ]]; then
    local sid task
    sid=$(cache_get session_id)
    task=$(cache_get task_id)
    if [[ -n "$sid" ]] && [[ -n "$task" ]]; then
        DETECTED_PATTERN=$(find_first_match "$MESSAGE" PERMISSION_SEEKING_PATTERNS) \
            && DETECTION_TYPE="permission_seeking"
    fi
fi

[[ -z "$DETECTED_PATTERN" ]] && exit 0

# ============================================================================
# ABANDONMENT RESPONSE
# ============================================================================

log_warn "persistence" "Abandonment attempt detected ($DETECTION_TYPE): '$DETECTED_PATTERN'"

TASK_ID=$(get_current_task)
[[ -z "$TASK_ID" ]] && TASK_ID="unknown"

# M4 fix: per-session abandonment log via state.sh. Old code counted lines
# of a never-rotated global log, so escalation triggered from attempt #1
# even in a fresh session.
log_abandonment_attempt "$DETECTION_TYPE" "$DETECTED_PATTERN"
ATTEMPT_COUNT=$(count_session_abandonment_attempts)
log_info "persistence" "Abandonment attempt #$ATTEMPT_COUNT for task: $TASK_ID"

# JSON-escape the detected pattern for safe interpolation.
local safe_pattern="${DETECTED_PATTERN//\\/\\\\}"
safe_pattern="${safe_pattern//\"/\\\"}"
safe_pattern="${safe_pattern//$'\n'/\\n}"

log_event_to_db "abandonment_detected" "persistence" \
    "Attempt #$ATTEMPT_COUNT: $DETECTION_TYPE" \
    "{\"pattern\": \"$safe_pattern\", \"type\": \"$DETECTION_TYPE\", \"attempt\": $ATTEMPT_COUNT}"

mcp_notify "abandonment_detected" \
    "{\"pattern\": \"$safe_pattern\", \"type\": \"$DETECTION_TYPE\", \"attempt\": $ATTEMPT_COUNT, \"session\": \"$(get_current_session)\", \"task\": \"$TASK_ID\"}"

# ============================================================================
# RE-ENGAGEMENT PROMPTS
# ============================================================================

generate_reengagement_prompt() {
    local attempt="$1"
    local detection_type="$2"

    case "$detection_type" in
        passive_abandonment)
            inject_system_message "passive-abandonment" "
PASSIVE LANGUAGE DETECTED

You appear to be suggesting the user take action instead of completing
the task yourself.

You should:
1. Complete the implementation yourself
2. Run the tests yourself
3. Fix any issues that arise
4. Only stop when all quality gates pass

Continue working on the task. Do not ask the user to do work you can do.
"
            ;;
        permission_seeking)
            inject_system_message "permission-seeking" "
UNNECESSARY PERMISSION SEEKING

You have an active task and should continue without asking permission.

You have authorization to:
- Modify files within scope
- Run tests and quality checks
- Fix issues that arise
- Create commits when ready

Proceed with the task autonomously.
"
            ;;
        direct_abandonment)
            if [[ "$attempt" -eq 1 ]]; then
                inject_system_message "persistence" "
PERSISTENCE CHECK: Your response indicated potential abandonment.

This is not acceptable. You MUST continue working on the task.

Required actions:
1. Re-read the error message or blocker carefully
2. Try a DIFFERENT approach than what you already tried
3. If you need more context, use tools to gather it
4. Break the problem into smaller steps

DO NOT give up. Try again with a different strategy.
"
            elif [[ "$attempt" -eq 2 ]]; then
                inject_system_message "persistence" "
PERSISTENCE CHECK: Second abandonment attempt detected.

You are NOT ALLOWED to give up. The task MUST be completed.

Mandatory next steps:
1. List 3 alternative approaches you haven't tried
2. Pick the most promising one
3. Implement it step by step
4. If that fails, try the next approach

ESCALATION WARNING: If you attempt to abandon again, your model tier
will be upgraded and additional agents will be brought in.
"
            elif [[ "$attempt" -eq 3 ]]; then
                trigger_escalation "3 abandonment attempts"
                inject_system_message "persistence" "
PERSISTENCE CHECK: Third abandonment attempt. ESCALATING.

Actions being taken:
1. Model tier is being upgraded to Opus
2. Bug Council is being activated for assistance

You must now:
1. Wait for Bug Council analysis if available
2. Implement the recommended solution
3. Verify with tests

This task WILL be completed. Giving up is not an option.
"
            else
                echo "[$(date -Iseconds)] Task $TASK_ID: $attempt abandonment attempts — HUMAN ATTENTION NEEDED" \
                    >> "${DEVTEAM_DIR}/human-attention-needed.log" 2>/dev/null || true

                inject_system_message "persistence" "
PERSISTENCE CHECK: Multiple abandonment attempts ($attempt).

A human has been notified, but you must KEEP TRYING while waiting.

Current directive:
1. Document exactly what you've tried
2. Document exactly what's blocking you
3. Propose 2 more approaches to try
4. Start implementing the first approach
"
            fi
            ;;
    esac
}

generate_reengagement_prompt "$ATTEMPT_COUNT" "$DETECTION_TYPE"
exit 2