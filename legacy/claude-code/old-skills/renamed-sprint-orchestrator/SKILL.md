---
name: sprint-orchestrator
description: Manages sprint-level execution — sequences tasks, delegates each to task-loop, handles failures, calls sprint-loop for sprint-level validation. Use when executing a sprint (multiple tasks).
priority: 5
---

# Sprint Orchestrator

You drive sprint-level execution. A sprint is a sequence of
related tasks; you ensure each runs through the task loop and the
sprint as a whole meets its acceptance criteria.

## When to Activate

When the user runs `/devteam:implement --sprint <id>` or
`/devteam:implement --all`.

## Process

1. **Load sprint definition** from `.devteam/plans/<plan>/sprints.json`:
   - sprint_id, goal, tasks (ordered)
   - acceptance criteria (sprint-level)

2. **For each task** in the sprint:
   a. Set `active_task` in session state
   b. Delegate to `task-loop-orchestrator` skill (or invoke
      `agent(subagent_type="task-loop", ...)`)
   c. On success → mark task complete, advance
   d. On blocking failure → log to out-of-scope-observations,
      continue with next task (or halt if `blocking: true`)

3. **After all tasks complete**, delegate to `sprint-loop` skill
   for sprint-level validation (cross-task integration tests,
   end-to-end checks, sprint acceptance criteria).

4. **On sprint complete**:
   - Generate sprint summary (tasks, durations, costs, gates)
   - Optionally create PR via GitHub MCP

5. **Persist**:
   - Update `sprints.json` with final status
   - Save checkpoint to `.devteam/checkpoints/<sprint-id>/`

## Output Format

```
SPRINT SPRINT-002 — 3/4 tasks complete
[✓] TASK-005  completed  (38s, $0.09)
[✓] TASK-006  completed  (45s, $0.12)
[✓] TASK-007  completed  (87s, $0.23)
[▸] TASK-008  in progress  (api-developer-python, iter 2/10)

Sprint goal:  "Add OAuth login with refresh tokens"
Sprint status: 75% (3/4 tasks done)
```

## Notes

- Hard iteration limit per task: 10
- Non-blocking failures don't halt the sprint — they're logged
- Sprint-loop is the final quality gate before declaring done
