---
description: "Run only Stage 2 (Development) of the Kotlin pipeline. Reads analysis.md and dispatches parallel implementation agents. Requires Stage 1 to be complete."
argument-hint: --feature "..." [--plan-id <id>] [--dry-run] [--pipeline.retry.per_agent=N]
---

# /devteam:develop

**IMMEDIATELY invoke the development-orchestrator agent.**
Do NOT implement anything yourself. Do NOT write code directly.

You MUST call the `agent()` tool with `subagent_type="development-orchestrator"`:

```
agent(subagent_type="development-orchestrator", prompt="/devteam:develop --feature \"<feature>\" [--flags]")
```

Run only the Development stage of the Kotlin + Spring backend
pipeline. Reads existing `analysis.md` and dispatches parallel
implementation agents.

## Pre-condition

`/devteam:analyze` (or equivalent manual analysis) must have been
run. The orchestrator finds `analysis.md` in
`.devteam/plans/<active-plan-id>/`.

## Usage

```bash
/devteam:develop
/devteam:develop --feature "Add OAuth login"   # auto-selects most recent plan
/devteam:develop --plan-id plan-add-oauth-login-20260616-a3f9
/devteam:develop --dry-run
```

## Process

Calls `development-orchestrator` directly. Skips Stages 1 and 3.

## Output

Code changes in 4 file partitions:
- API layer (`**/api/`, `**/controller/`, `**/routes/`, `**/dto/`)
- Data layer (`**/domain/`, `**/entity/`, `**/repository/`, `db/migration/`)
- Config (`application*.yml`, `logback*.xml`, `gradle.properties`)
- Integration (`**/client/`, `**/infrastructure/`, `**/event/`, `**/messaging/`)

Plus `stage2.merge.md` with overlap check and build verification.

## Tips

- Use after `/devteam:analyze` or `/devteam:build --skip-stage development`
- Use `--dry-run` to see partition ownership
