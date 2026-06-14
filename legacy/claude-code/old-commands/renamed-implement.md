---
description: Execute plans, sprints, tasks, or ad-hoc work with Task Loop.
argument-hint: [task] [--sprint <id>] [--all] [--task <id>] [--eco] [--skip-interview] [--type <type>]
---

# /devteam:implement

Run autonomous implementation with iterative quality loop and model
escalation.

## Usage

```bash
/devteam:implement                          # current/selected plan
/devteam:implement --sprint 1               # specific sprint
/devteam:implement --sprint SPRINT-001      # by ID
/devteam:implement --all                    # all sprints sequentially
/devteam:implement --task TASK-001          # specific task
/devteam:implement "Add pagination to list" # ad-hoc
/devteam:implement --eco                    # cost-optimized
/devteam:implement --skip-interview         # skip ad-hoc interview
/devteam:implement --type security          # hint for agent selection
```

## Process

### Phase 0: Determine Target

Priority:
1. `--task <id>` → single task
2. `--sprint <id>` → single sprint
3. `--all` → all sprints
4. Ad-hoc description (positional arg) → create new task
5. No args → current/selected plan

### Phase 1: Initialize

If ad-hoc and description is ambiguous, ask 1-3 clarifying questions.
Skip if `--skip-interview`.

### Phase 2: Agent Selection

Pick agents based on file types, keywords, and task type. Default
selection rules:

| Task type | Primary agent |
|---|---|
| feature (backend) | `api-developer-python` or `api-developer-typescript` |
| feature (frontend) | `frontend-developer` |
| bug | `root-cause-analyst` (then Bug Council if escalated) |
| security | `security-auditor` |
| refactor | `refactoring-coordinator` |
| docs | inline (no agent) |

### Phase 3: Execute via Task Loop

For each task, run the iterative quality loop:

```
Execute selected agent(s)
        │
        ▼
Scope validator: are changes in-scope?
        │
        ▼
Quality gate enforcer: tests, lint, types, security
        │
        ▼
Requirements validator: acceptance criteria met?
        │
   ┌────┴────┐
PASS│        │FAIL
   │         │
   ▼         ▼
COMPLETE   Increment failures → escalate model tier (if threshold)
             │
             ▼
           Loop back to Execute with stricter context
             │
             ▼
           After N consecutive failures → Bug Council
```

Use the `agent` tool to invoke subagents:

```python
agent(
    subagent_type="task-loop",  # the orchestrator
    prompt="Execute TASK-001 with quality gates: tests, lint, types, security."
)
```

### Phase 4: Completion

When all quality gates pass:

```text
TASK COMPLETE: TASK-001
EXIT_SIGNAL: true
```

The `Stop` hook will see this and allow session exit.

### Error Recovery

| Failure | Action |
|---|---|
| Agent timeout | Retry with extended context |
| Scope violation | Revert out-of-scope files, retry with stricter scope |
| Quality gate fail | Create fix task, increment failure counter |
| Stuck loop (3x same error) | Escalate to Bug Council via `bug-council-orchestrator` |
| Max iterations (default 10) | Halt, report to user |

## Tips

- Use `--eco` for simple changes (e.g., docs, config) to save cost.
- Keep tasks small (≤ 8 complexity points) for predictable loops.
- Read `.devteam/plans/<plan-id>/prd.md` for context before starting.
