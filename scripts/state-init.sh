#!/bin/bash
# DevTeam State Initialization (v6.2 — file-based, no SQLite)
# Creates the .devteam/state/ directory structure.
# No external binary requirement (works on macOS, Linux, Windows).
#
# Usage: source this file, or call directly:
#   bash scripts/state-init.sh [project_root]

set -euo pipefail

# Paths
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(pwd)}"
STATE_DIR="${ROOT}/.devteam/state"

# Colors (declare only if not already set by common.sh)
[[ -z "${COLOR_GREEN:-}" ]] && readonly COLOR_GREEN='\033[0;32m'
[[ -z "${COLOR_YELLOW:-}" ]] && readonly COLOR_YELLOW='\033[1;33m'
[[ -z "${COLOR_RED:-}" ]] && readonly COLOR_RED='\033[0;31m'
[[ -z "${COLOR_NC:-}" ]] && readonly COLOR_NC='\033[0m'

log_info()  { echo -e "${COLOR_GREEN}[devteam]${COLOR_NC} $1"; }
log_warn()  { echo -e "${COLOR_YELLOW}[devteam]${COLOR_NC} $1"; }
log_error() { echo -e "${COLOR_RED}[devteam]${COLOR_NC} $1" >&2; }

# ============================================================================
# CREATE DIRECTORY STRUCTURE
# ============================================================================

log_info "Initializing DevTeam state in ${STATE_DIR}/"

mkdir -p "${STATE_DIR}/sessions"
mkdir -p "${STATE_DIR}/kv"
mkdir -p "${STATE_DIR}/events"
mkdir -p "${STATE_DIR}/tasks"
mkdir -p "${STATE_DIR}/agent-runs"

# ============================================================================
# INITIALIZE EMPTY FILES
# ============================================================================

# current-session.md (pointer to active session)
[[ -f "${STATE_DIR}/current-session.md" ]] || \
    echo "" > "${STATE_DIR}/current-session.md"

# circuit-breaker.md (closed state by default)
[[ -f "${STATE_DIR}/circuit-breaker.md" ]] || cat > "${STATE_DIR}/circuit-breaker.md" <<'EOF'
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

# gates.md (append-only quality gate log)
[[ -f "${STATE_DIR}/gates.md" ]] || cat > "${STATE_DIR}/gates.md" <<'EOF'
# Quality Gates
EOF

# Today's events file
TODAY=$(date +%Y-%m-%d)
[[ -f "${STATE_DIR}/events/${TODAY}-events.md" ]] || \
    echo "# Events ${TODAY}" > "${STATE_DIR}/events/${TODAY}-events.md"

# ============================================================================
# WARN ABOUT LEGACY v6.1 SQLite
# ============================================================================

LEGACY_DB="${ROOT}/.devteam/devteam.db"
if [[ -f "$LEGACY_DB" ]]; then
    log_warn "Legacy SQLite database found: $LEGACY_DB"
    log_warn "DevTeam v6.2 uses file-based state at $STATE_DIR/"
    log_warn ""
    log_warn "To migrate, run:"
    log_warn "  bash scripts/state-migrate-v61-to-v62.sh"
    log_warn ""
    log_warn "Or, if starting fresh, simply delete the legacy DB:"
    log_warn "  rm $LEGACY_DB"
fi

# ============================================================================
# SUMMARY
# ============================================================================

log_info "DevTeam state initialized successfully"
echo ""
echo "State directory layout:"
echo "  ${STATE_DIR}/"
echo "  ├── current-session.md          # pointer to active session"
echo "  ├── sessions/                   # per-session MD files"
echo "  ├── kv/                          # one file per KV key"
echo "  ├── events/                      # append-only daily log"
echo "  ├── tasks/                       # per-task MD files"
echo "  ├── agent-runs/                  # per-agent-run MD files"
echo "  ├── circuit-breaker.md          # circuit breaker state"
echo "  └── gates.md                     # quality gate log"

# Verify
[[ -d "${STATE_DIR}/sessions" ]] && [[ -d "${STATE_DIR}/kv" ]] && \
    log_info "Verification passed"

# If executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    :  # already ran main logic above
fi
