---
description: Set the active plan for subsequent /devteam:implement calls.
argument-hint: <plan-id>
---

# /devteam:select

Choose which plan is active. Subsequent `/devteam:implement` calls
will target this plan by default.

## Usage

```bash
/devteam:list                # see available plans
/devteam:select oauth-v2     # set active
```

## Process

1. Verify `<plan-id>` exists in `.devteam/plans/<plan-id>/`.
2. Update `.devteam/config.yaml`:
   ```yaml
   active_plan: oauth-v2
   ```
3. Confirm.

## Output

```text
Active plan: oauth-v2

Sprints:
  1. SPRINT-001  ✓  3/3
  2. SPRINT-002  ◐  2/4
  3. SPRINT-003  ○  0/2

Next: /devteam:implement to continue
```

## Notes

- The active plan is just a default. You can always target a
  specific plan with `/devteam:implement --sprint <id>`.
- To clear: `rm` the `active_plan` key from config (or set to `null`).
