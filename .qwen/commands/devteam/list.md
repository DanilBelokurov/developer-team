---
description: List all plans, sprints, and tasks.
---

# /devteam:list

Show all plans and their progress.

## Usage

```bash
/devteam:list            # all plans
/devteam:list --active   # only the active plan
```

## Output

```text
══════════════════════════════════════════
 DevTeam Plans
══════════════════════════════════════════

○ oauth-login-v2          (active)
  ├─ SPRINT-001  ✓  3/3 tasks
  ├─ SPRINT-002  ◐  2/4 tasks  (in progress)
  └─ SPRINT-003  ○  0/2 tasks

○ rate-limiter-v1         (completed 2026-05-30)
  └─ SPRINT-001  ✓  5/5 tasks

○ api-refactor            (paused)
  └─ SPRINT-001  ◐  1/3 tasks

══════════════════════════════════════════
```

## Implementation

1. Read `.devteam/plans/` for all plan directories
2. For each, read `sprints.json` and aggregate task counts by status
3. Highlight the active plan (from `.devteam/config.yaml` `active_plan`
   key, default: most recently created)
