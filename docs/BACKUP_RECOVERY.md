# Backup and Recovery Guide

File-based state backup and recovery for DevTeam.

## What Gets Backed Up

| Path | Contents | Priority |
|------|----------|----------|
| `.devteam/state/sessions/` | Session metadata and state | High |
| `.devteam/state/events/` | Event logs (`YYYY-MM-DD-events.md`) | Medium |
| `.devteam/state/kv/` | Key-value state (plan-isolated) | High |
| `.devteam/state/tasks/` | Task definitions | High |
| `.devteam/state/gates.md` | Quality gate status | Medium |
| `.devteam/state/agent-runs/` | Agent run records | Low |
| `.devteam/state/circuit-breaker.md` | Circuit breaker state | Medium |
| `.devteam/memory/` | Session memory snapshots | Medium |

## Automatic Backups

State is versioned via `.devteam/` gitignore. No automatic cron needed — git provides history.

## Manual Backup

```bash
# Simple tar backup
tar -czf devteam-state-$(date +%Y%m%d).tar.gz .devteam/

# Backup specific state
cp -r .devteam/state .devteam/state.backup-$(date +%Y%m%d)
```

## Recovery

```bash
# Restore from git
git checkout HEAD -- .devteam/

# Restore from tar
tar -xzf devteam-state-YYYYMMDD.tar.gz

# Restore specific directory
cp -r .devteam/state.backup-YYYYMMDD/state .devteam/
```

## Validation

```bash
# Check state directory integrity
ls .devteam/state/sessions/
ls .devteam/state/events/
cat .devteam/state/gates.md
```
