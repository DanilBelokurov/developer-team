#!/bin/bash
# DevTeam Progress Summary Generator
# Creates and updates human-readable progress.txt file
#
# Usage: source this file in hooks and commands
#   source "$(dirname "$0")/../scripts/progress.sh"

set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/state.sh"

# Progress file path
DEVTEAM_PROGRESS_FILE="${DEVTEAM_DIR:-".devteam"}/progress.txt"
DEVTEAM_FEATURES_FILE="${DEVTEAM_DIR:-".devteam"}/features.json"

# ============================================================================
# PROGRESS FILE GENERATION
# ============================================================================

# L9 fix: debounce generate_progress_summary. Each feature mutation used to
# trigger a full progress regeneration (git log + 5 jq + session reads).
# Now we only regenerate at most once every PROGRESS_DEBOUNCE_SECS, unless
# PROGRESS_FORCE=1 is set.
PROGRESS_DEBOUNCE_SECS="${PROGRESS_DEBOUNCE_SECS:-2}"
PROGRESS_LAST_GENERATED_FILE="${DEVTEAM_DIR:-.devteam}/.progress-last-ts"

_maybe_regenerate_progress() {
    [[ "${PROGRESS_FORCE:-0}" == "1" ]] && { generate_progress_summary; return; }
    local now last=0
    now=$(date +%s)
    [[ -f "$PROGRESS_LAST_GENERATED_FILE" ]] && last=$(cat "$PROGRESS_LAST_GENERATED_FILE" 2>/dev/null || echo 0)
    if (( now - last >= PROGRESS_DEBOUNCE_SECS )); then
        generate_progress_summary
        echo "$now" > "$PROGRESS_LAST_GENERATED_FILE" 2>/dev/null || true
    fi
}

# ============================================================================
# PROGRESS FILE GENERATION (continued)
# ============================================================================

# Generate progress summary
# Args: [session_id]
generate_progress_summary() {
    local session_id="${1:-}"

    if [ -z "$session_id" ]; then
        session_id=$(get_current_session_id 2>/dev/null || echo "")
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local project_name
    project_name=$(basename "$(pwd)")

    # Check jq dependency for feature stats
    if ! command -v jq &>/dev/null; then
        log_warn "jq not available" "progress"
        return 1
    fi

    # Get feature stats if features.json exists
    local total_features=0
    local passing_features=0
    local failing_features=0
    local pass_percentage=0

    if [ -f "$DEVTEAM_FEATURES_FILE" ]; then
        total_features=$(jq '.features | length' "$DEVTEAM_FEATURES_FILE" 2>/dev/null || echo "0")
        passing_features=$(jq '[.features[] | select(.passes == true)] | length' "$DEVTEAM_FEATURES_FILE" 2>/dev/null || echo "0")
        failing_features=$((total_features - passing_features))
        if [ "$total_features" -gt 0 ]; then
            pass_percentage=$((passing_features * 100 / total_features))
        fi
    fi

    # Get recent commits
    local recent_commits
    recent_commits=$(git log --oneline -5 2>/dev/null || echo "No commits yet")

    # Get current session info from file-based state
    local current_phase=""
    local current_iteration=0
    local session_status=""

    if [ -n "$session_id" ]; then
        current_phase=$(get_current_phase 2>/dev/null || echo "")
        current_iteration=$(get_current_iteration 2>/dev/null || echo "0")
        session_status=$(get_state "status" 2>/dev/null || echo "")
    fi

    # Generate the progress file
    cat > "$DEVTEAM_PROGRESS_FILE" << EOF
═══════════════════════════════════════════════════════════════
DEVTEAM PROGRESS TRACKER
═══════════════════════════════════════════════════════════════

Project: ${project_name}
Last Updated: ${timestamp}
Session: ${session_id:-"None active"}
Status: ${session_status:-"N/A"}

───────────────────────────────────────────────────────────────
FEATURE STATUS
───────────────────────────────────────────────────────────────
Total Features: ${total_features}
Passing: ${passing_features} (${pass_percentage}%)
Failing: ${failing_features}

Progress Bar: $(generate_progress_bar "$passing_features" "$total_features")

───────────────────────────────────────────────────────────────
SESSION INFO
───────────────────────────────────────────────────────────────
Current Phase: ${current_phase:-"N/A"}
Iteration: ${current_iteration}

───────────────────────────────────────────────────────────────
RECENT COMMITS
───────────────────────────────────────────────────────────────
${recent_commits}

───────────────────────────────────────────────────────────────
NEXT STEPS
───────────────────────────────────────────────────────────────
$(get_next_feature)

═══════════════════════════════════════════════════════════════
EOF

    log_info "Progress summary updated: $DEVTEAM_PROGRESS_FILE" "progress"

    # Note: progress data is stored in features.json (file-based)
    # No database sync needed
}

# Generate ASCII progress bar
# Args: current, total
generate_progress_bar() {
    local current="${1:-0}"
    local total="${2:-0}"
    local width=40

    if [ "$total" -eq 0 ]; then
        echo "[$(printf '%*s' $width '' | tr ' ' '-')]  0%"
        return
    fi

    local filled=$((current * width / total))
    local empty=$((width - filled))
    local percent=$((current * 100 / total))

    local bar="["
    bar+=$(printf '%*s' $filled '' | tr ' ' '█')
    bar+=$(printf '%*s' $empty '' | tr ' ' '░')
    bar+="] ${percent}%"

    echo "$bar"
}

# Get next feature to work on
get_next_feature() {
    if [ ! -f "$DEVTEAM_FEATURES_FILE" ]; then
        echo "No features.json found. Run initializer phase first."
        return
    fi

    local next_feature
    next_feature=$(jq -r '
        .features
        | map(select(.passes == false))
        | sort_by(
            if .priority == "critical" then 0
            elif .priority == "high" then 1
            elif .priority == "medium" then 2
            else 3
            end
        )
        | .[0]
        | if . then "[\(.id)] \(.description)" else "All features complete!" end
    ' "$DEVTEAM_FEATURES_FILE" 2>/dev/null)

    echo "${next_feature:-"Unable to determine next feature"}"
}

# ============================================================================
# FEATURE TRACKING
# ============================================================================

# Mark a feature as passing
# Args: feature_id
mark_feature_passing() {
    local feature_id="$1"

    if [ ! -f "$DEVTEAM_FEATURES_FILE" ]; then
        log_error "features.json not found" "progress"
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # File locking to prevent race conditions (H8/H9 fix)
    # Reuse state.sh's acquire_lock: mkdir + brief retry (no busy-wait).
    local lock_dir="${DEVTEAM_FEATURES_FILE}.lock"
    # Clean stale locks: held by a dead process.
    if [ -d "$lock_dir" ]; then
        local lock_pid_file="${lock_dir}/pid"
        if [ -f "$lock_pid_file" ]; then
            local lock_pid
            lock_pid=$(cat "$lock_pid_file" 2>/dev/null || echo "0")
            if [ "$lock_pid" != "0" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
                rm -rf "$lock_dir" 2>/dev/null || true
            fi
        fi
    fi
    if ! acquire_lock "$lock_dir"; then
        log_warn "Could not acquire features.json lock" "progress"
        return 1
    fi
    echo $$ > "${lock_dir}/pid" 2>/dev/null || true
    # Single robust trap (RETURN+ERR+INT+TERM) — fixes H9 leak.
    trap "rm -rf '$lock_dir' 2>/dev/null; trap - RETURN ERR INT TERM" RETURN ERR INT TERM

    # Update the feature
    local tmp_file
    tmp_file=$(safe_mktemp)

    jq --arg id "$feature_id" --arg ts "$timestamp" '
        .features = [.features[] |
            if .id == $id then
                .passes = true |
                .verified_at = $ts |
                .steps = [.steps[] | .passes = true]
            else .
            end
        ] |
        .updated_at = $ts
    ' "$DEVTEAM_FEATURES_FILE" > "$tmp_file"

    mv "$tmp_file" "$DEVTEAM_FEATURES_FILE"

    log_info "Feature $feature_id marked as passing" "progress"

    # Update progress file (debounced — L9 fix)
    _maybe_regenerate_progress
}

# Mark a feature as failing
# Args: feature_id, reason
mark_feature_failing() {
    local feature_id="$1"
    local reason="${2:-"Verification failed"}"

    if [ ! -f "$DEVTEAM_FEATURES_FILE" ]; then
        log_error "features.json not found" "progress"
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # File locking to prevent race conditions (H8/H9 fix)
    local lock_dir="${DEVTEAM_FEATURES_FILE}.lock"
    if [ -d "$lock_dir" ]; then
        local lock_pid_file="${lock_dir}/pid"
        if [ -f "$lock_pid_file" ]; then
            local lock_pid
            lock_pid=$(cat "$lock_pid_file" 2>/dev/null || echo "0")
            if [ "$lock_pid" != "0" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
                rm -rf "$lock_dir" 2>/dev/null || true
            fi
        fi
    fi
    if ! acquire_lock "$lock_dir"; then
        log_warn "Could not acquire features.json lock" "progress"
        return 1
    fi
    echo $$ > "${lock_dir}/pid" 2>/dev/null || true
    trap "rm -rf '$lock_dir' 2>/dev/null; trap - RETURN ERR INT TERM" RETURN ERR INT TERM

    local tmp_file
    tmp_file=$(safe_mktemp)

    jq --arg id "$feature_id" --arg ts "$timestamp" --arg reason "$reason" '
        .features = [.features[] |
            if .id == $id then
                .passes = false |
                .last_failure = $reason |
                .updated_at = $ts
            else .
            end
        ] |
        .updated_at = $ts
    ' "$DEVTEAM_FEATURES_FILE" > "$tmp_file"

    mv "$tmp_file" "$DEVTEAM_FEATURES_FILE"

    log_warn "Feature $feature_id marked as failing: $reason" "progress"

    # Update progress file
    generate_progress_summary
}

# Get feature status
# Args: feature_id
get_feature_status() {
    local feature_id="$1"

    if [ ! -f "$DEVTEAM_FEATURES_FILE" ]; then
        echo "unknown"
        return
    fi

    jq -r --arg id "$feature_id" '
        .features[] | select(.id == $id) | if .passes then "passing" else "failing" end
    ' "$DEVTEAM_FEATURES_FILE" 2>/dev/null || echo "unknown"
}


# ============================================================================
# INITIALIZATION
# ============================================================================

# Create initial features.json from PRD or task list
# Args: plan_id
initialize_features_json() {
    local plan_id="${1:-}"

    local project_name
    project_name=$(basename "$(pwd)")

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create initial structure
    cat > "$DEVTEAM_FEATURES_FILE" << EOF
{
  "project_name": "${project_name}",
  "plan_id": "${plan_id}",
  "created_at": "${timestamp}",
  "updated_at": "${timestamp}",
  "features": []
}
EOF

    log_info "Initialized features.json" "progress"
}

# Add a feature to features.json
# Args: id, category, description, priority, steps_json
add_feature() {
    local id="$1"
    local category="$2"
    local description="$3"
    local priority="${4:-medium}"
    local steps_json="${5:-"[]"}"

    if [ ! -f "$DEVTEAM_FEATURES_FILE" ]; then
        initialize_features_json
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local tmp_file
    tmp_file=$(safe_mktemp)

    jq --arg id "$id" \
       --arg cat "$category" \
       --arg desc "$description" \
       --arg pri "$priority" \
       --argjson steps "$steps_json" \
       --arg ts "$timestamp" '
        .features += [{
            "id": $id,
            "category": $cat,
            "description": $desc,
            "priority": $pri,
            "steps": $steps,
            "passes": false
        }] |
        .updated_at = $ts
    ' "$DEVTEAM_FEATURES_FILE" > "$tmp_file"

    mv "$tmp_file" "$DEVTEAM_FEATURES_FILE"

    log_info "Added feature $id" "progress"
}

# ============================================================================
# MAIN
# ============================================================================

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        generate)
            generate_progress_summary "${2:-}"
            ;;
        sync)
            log_info "Progress is file-based; use generate to update" "progress"
            ;;
        mark-passing)
            mark_feature_passing "${2:-}"
            ;;
        mark-failing)
            mark_feature_failing "${2:-}" "${3:-}"
            ;;
        status)
            get_feature_status "${2:-}"
            ;;
        sync)
            log_info "Progress is file-based; use generate to update" "progress"
            ;;
        init)
            initialize_features_json "${2:-}"
            ;;
        add)
            add_feature "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-"[]"}"
            ;;
        *)
            echo "Usage: $0 {generate|mark-passing|mark-failing|status|sync|init|add} [args]"
            exit 1
            ;;
    esac
fi
