---
description: Interactive planning — interview, research, PRD, task graph, sprints.
argument-hint: [--feature "<text>"] [--from <file>] [--skip-research]
---

# /devteam:plan

Generate a complete plan: PRD, dependency graph, and sprints.

## Usage

```bash
/devteam:plan                              # interactive interview
/devteam:plan --feature "Add OAuth login"  # from feature description
/devteam:plan --from spec.md              # plan from a spec file
/devteam:plan --skip-research              # skip research phase
```

## Process

### Phase 1: Interview

If no `--feature` and no `--from`, conduct a structured interview:

1. **Goal** — what user-visible outcome is desired?
2. **Acceptance criteria** — how do we know it's done?
3. **Constraints** — performance, security, compatibility, deadlines.
4. **Out of scope** — explicit boundaries.
5. **Stack** — languages, frameworks, infrastructure.
6. **Scale** — expected load, data volume, team size.

Use `ask_user_question` for each. Allow `--skip-interview` to bypass
when context is already clear (e.g., `--feature "…"` with detail).

### Phase 2: Research

If not `--skip-research`, delegate to **research** exploration (use
`agent` tool with subagent_type "Explore" or read
`agents/diagnosis/code-archaeologist.md` for a guided research
template). Surface:

- Existing patterns in the codebase
- Tech-stack fit
- Identified blockers
- Reusable components

### Phase 3: PRD

Write `.devteam/plans/<plan-id>/prd.md`:

```markdown
# PRD: <feature name>

## Problem
<why this is needed>

## Goals
- <measurable goal 1>
- <measurable goal 2>

## Non-goals
- <out of scope>

## Acceptance Criteria
- [ ] <criterion 1>
- [ ] <criterion 2>

## Technical Approach
<approach summary>

## Risks
- <risk 1> → <mitigation>
```

### Phase 4: Task Graph

Analyze the PRD and decompose into a dependency-ordered task graph.
Write to `.devteam/plans/<plan-id>/tasks.json`:

```json
{
  "tasks": [
    {
      "id": "TASK-001",
      "title": "...",
      "depends_on": [],
      "estimated_complexity": 5,
      "agent_type": "api-developer-python",
      "acceptance": ["..."]
    }
  ]
}
```

### Phase 5: Sprints

Group tasks into sprints respecting dependencies and complexity
budget. Default sprint capacity: 20 complexity points. Write to
`.devteam/plans/<plan-id>/sprints.json`.

### Phase 6: Completion

```text
PLAN CREATED

Plan ID: <plan-id>
Sprints: <count>
Tasks: <count>

Next: /devteam:implement to begin execution
```

## Tips

- One PRD per plan. If scope grows, create a new plan.
- Acceptance criteria must be testable.
- Aim for 3-8 tasks per sprint.
