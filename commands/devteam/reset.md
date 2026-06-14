---
description: Reset stuck sessions, clear circuit breaker, archive failures.
---

# /devteam:reset

Recover from stuck or failed autonomous sessions.

## Usage

```bash
/devteam:reset               # current session
/devteam:reset --all         # all stuck sessions
/devteam:reset --circuit     # clear circuit breaker only
```

## Process

1. **Identify stuck sessions**: tasks with `status=in_progress` and no
   update in >30 minutes, OR `current_iteration >= max_iterations`.
2. **For each stuck session**:
   - Mark tasks as `interrupted`
   - Save checkpoint to `.devteam/checkpoints/<session-id>/`
   - Update session `status=interrupted`, `ended_at=now`
3. **Clear circuit breaker** if `--circuit` or default:
   - Reset `consecutive_failures` to 0
   - Reset `circuit_breaker_open` to false
4. **Archive recent failures** (last 24h) to `.devteam/logs/failures-<date>.log`

## Output

```text
══════════════════════════════════════════
 DevTeam Reset
══════════════════════════════════════════

Reset sessions:
  ✓ session-20260613-142530-a3f9  (1 task interrupted, checkpoint saved)
  
Circuit breaker:
  ✓ cleared (was at 3/5 failures)

Archived 4 failure events to .devteam/logs/failures-20260613.log

Run /devteam:implement to resume.

══════════════════════════════════════════
```

## Notes

- This is non-destructive. Tasks are marked interrupted, not deleted.
- Resumable via `/devteam:implement` (will read interrupted tasks and
  offer to resume or restart).
- Does NOT touch `.devteam/devteam.db` itself, only session state.
