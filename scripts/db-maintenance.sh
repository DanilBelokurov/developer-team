#!/bin/bash
# maintenance.sh - File-based state maintenance (v6.2, no SQLite)
# Performs routine maintenance on the file-based state directory
#
# Usage:
#   ./db-maintenance.sh [command]
#
# Commands:
#   cleanup   - Remove old session/event files
#   backup   - Create state directory backup
#   check    - Verify state directory integrity
#   stats    - Show state directory statistics
#   all      - Run all maintenance tasks
#
# Example:
#   ./db-maintenance.sh all
#   ./db-maintenance.sh backup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
DEVTEAM_DIR="${PROJECT_ROOT}/.devteam"
STATE_DIR="${DEVTEAM_DIR}/state"
BACKUP_DIR="${DEVTEAM_DIR}/backups"
MAX_BACKUPS=5
RETENTION_DAYS="${RETENTION_DAYS:-30}"

setup_maintenance_dirs() {
    mkdir -p "$STATE_DIR" "$BACKUP_DIR"
}

log_info "Running maintenance..." "maintenance"

# ============================================================================
# CLEANUP - Remove old state files
# ============================================================================

cmd_cleanup() {
    log_info "Cleaning up state files older than $RETENTION_DAYS days..." "maintenance"

    local cutoff_ts
    cutoff_ts=$(date -d "$RETENTION_DAYS days ago" +%s 2>/dev/null || date -v-${RETENTION_DAYS}d +%s)

    local cleaned=0

    # Clean old event files (older than retention)
    if [ -d "$STATE_DIR/events" ]; then
        for event_file in "$STATE_DIR/events"/*-events.md; do
            [ -f "$event_file" ] || continue
            local file_ts
            file_ts=$(stat -c %Y "$event_file" 2>/dev/null || stat -f %m "$event_file" 2>/dev/null || echo 0)
            if [ "$file_ts" -lt "$cutoff_ts" ]; then
                rm -f "$event_file"
                cleaned=$((cleaned + 1))
            fi
        done
    fi

    # Clean empty agent-run files
    if [ -d "$STATE_DIR/agent-runs" ]; then
        for run_file in "$STATE_DIR/agent-runs"/*.md; do
            [ -f "$run_file" ] || continue
            if [ ! -s "$run_file" ]; then
                rm -f "$run_file"
                cleaned=$((cleaned + 1))
            fi
        done
    fi

    # Clean empty task files
    if [ -d "$STATE_DIR/tasks" ]; then
        for task_file in "$STATE_DIR/tasks"/*.md; do
            [ -f "$task_file" ] || continue
            if [ ! -s "$task_file" ]; then
                rm -f "$task_file"
                cleaned=$((cleaned + 1))
            fi
        done
    fi

    log_info "Cleanup complete. Removed $cleaned old/empty files." "maintenance"
}

# ============================================================================
# BACKUP - Create state directory backup
# ============================================================================

cmd_backup() {
    log_info "Creating state directory backup..." "maintenance"

    mkdir -p "$BACKUP_DIR"

    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')
    local backup_file="$BACKUP_DIR/state-$timestamp.tar.gz"

    if [ ! -d "$STATE_DIR" ] || [ -z "$(ls -A "$STATE_DIR" 2>/dev/null)" ]; then
        log_info "Nothing to backup (state directory empty)" "maintenance"
        return 0
    fi

    if ! tar -czf "$backup_file" -C "$DEVTEAM_DIR" state 2>/dev/null; then
        log_error "Backup failed" "maintenance"
        return 1
    fi

    log_info "Backup created: $backup_file" "maintenance"

    # Rotate old backups
    local backup_count
    backup_count=$(find "$BACKUP_DIR" -name "state-*.tar.gz" -type f | wc -l)
    backup_count=$((backup_count))

    if [ "$backup_count" -gt "$MAX_BACKUPS" ]; then
        log_info "Rotating old backups (keeping $MAX_BACKUPS)..." "maintenance"
        local to_delete=$((backup_count - MAX_BACKUPS))
        find "$BACKUP_DIR" -name "state-*.tar.gz" -type f | \
            sort | \
            head -n "$to_delete" | \
            xargs rm -f
    fi

    log_info "Backup complete" "maintenance"
}

# ============================================================================
# CHECK - Verify state directory integrity
# ============================================================================

cmd_check() {
    log_info "Checking state directory integrity..." "maintenance"

    local errors=0

    # Check required directories exist
    for dir in sessions kv events tasks; do
        if [ -d "$STATE_DIR/$dir" ]; then
            log_info "  $dir/ OK" "maintenance"
        else
            log_warn "  $dir/ missing (will be created on demand)" "maintenance"
        fi
    done

    # Check YAML frontmatter integrity in session files
    if [ -d "$STATE_DIR/sessions" ]; then
        for session_file in "$STATE_DIR/sessions"/*.md; do
            [ -f "$session_file" ] || continue
            # Verify YAML frontmatter has required fields
            if ! grep -q "^---$" "$session_file" 2>/dev/null; then
                log_warn "  Session file missing frontmatter: $(basename "$session_file")" "maintenance"
                errors=$((errors + 1))
            fi
        done
        log_info "  $(find "$STATE_DIR/sessions" -name '*.md' | wc -l) session files checked" "maintenance"
    fi

    # Check for stuck locks (directories older than 30 seconds)
    if find "$STATE_DIR" -name "*.lock" -type d -mmin +30 2>/dev/null | grep -q .; then
        log_warn "  Found stale lock directories (older than 30 minutes)" "maintenance"
        errors=$((errors + 1))
    else
        log_info "  No stale locks found" "maintenance"
    fi

    if [ "$errors" -eq 0 ]; then
        log_info "State integrity check passed" "maintenance"
    else
        log_warn "State integrity check found $errors issues" "maintenance"
    fi
}

# ============================================================================
# STATS - Show state directory statistics
# ============================================================================

cmd_stats() {
    log_info "State Directory Statistics" "maintenance"

    echo ""
    echo "=== State Directory Size ==="
    local size
    size=$(du -sb "$STATE_DIR" 2>/dev/null | cut -f1 || echo 0)
    local size_mb
    size_mb=$(echo "scale=2; $size / 1024 / 1024" | bc 2>/dev/null || echo "?")
    echo "Size: $size bytes ($size_mb MB)"

    echo ""
    echo "=== File Counts ==="
    local sessions sessions_active events tasks agent_runs kv_keys
    sessions=$(find "$STATE_DIR/sessions" -name '*.md' 2>/dev/null | wc -l)
    events=$(find "$STATE_DIR/events" -name '*.md' 2>/dev/null | wc -l)
    tasks=$(find "$STATE_DIR/tasks" -name '*.md' 2>/dev/null | wc -l)
    agent_runs=$(find "$STATE_DIR/agent-runs" -name '*.md' 2>/dev/null | wc -l)
    kv_keys=$(find "$STATE_DIR/kv" -type f 2>/dev/null | wc -l)

    printf "  %-20s %s\n" "Sessions:" "$sessions"
    printf "  %-20s %s\n" "Event logs:" "$events"
    printf "  %-20s %s\n" "Tasks:" "$tasks"
    printf "  %-20s %s\n" "Agent runs:" "$agent_runs"
    printf "  %-20s %s\n" "KV keys:" "$kv_keys"

    echo ""
    echo "=== Recent Sessions ==="
    if [ -d "$STATE_DIR/sessions" ]; then
        find "$STATE_DIR/sessions" -name '*.md' -type f -printf '%T@ %p\n' 2>/dev/null | \
            sort -rn | head -5 | \
            while read -r ts path; do
                local name
                name=$(basename "$path")
                local status
                status=$(grep -m1 '^status:' "$path" 2>/dev/null | cut -d: -f2 | tr -d ' ' || echo 'unknown')
                printf "  %-30s %s\n" "$name" "$status"
            done
    fi

    echo ""
    echo "=== Backups ==="
    local backup_count backup_size
    backup_count=$(find "$BACKUP_DIR" -name "state-*.tar.gz" -type f 2>/dev/null | wc -l)
    if [ "$backup_count" -gt 0 ]; then
        backup_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "?")
        printf "  %-20s %s\n" "Count:" "$backup_count"
        printf "  %-20s %s\n" "Total size:" "$backup_size"
    else
        echo "  No backups found"
    fi
}

# ============================================================================
# RUN ALL
# ============================================================================

cmd_all() {
    log_info "Running all maintenance tasks..." "maintenance"
    cmd_backup
    cmd_cleanup
    cmd_check
    cmd_stats
    log_info "All maintenance tasks complete" "maintenance"
}

# ============================================================================
# MAIN
# ============================================================================

show_help() {
    echo "DevTeam State Maintenance (v6.2, file-based)"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  cleanup   Remove old/empty state files (>$RETENTION_DAYS days)"
    echo "  backup    Create state directory backup (tar.gz)"
    echo "  check     Verify state directory integrity"
    echo "  stats     Show state directory statistics"
    echo "  all       Run all maintenance tasks"
    echo ""
    echo "Environment:"
    echo "  DEVTEAM_DIR       Base directory (default: .devteam)"
    echo "  RETENTION_DAYS    Days to retain files (default: 30)"
    echo ""
}

main() {
    local command="${1:-help}"

    setup_maintenance_dirs

    case "$command" in
        cleanup) cmd_cleanup ;;
        backup)  cmd_backup ;;
        check)   cmd_check ;;
        stats)   cmd_stats ;;
        all)     cmd_all ;;
        help|-h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown command: $command" "maintenance"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
