---
description: "Run only Stage 1 (Analytics) of the Kotlin pipeline. Produces analysis.md. Use for planning without implementation."
argument-hint: --feature "..." [--dry-run]
---

# /devteam:analyze

Run only the Analytics stage of the Kotlin + Spring backend
pipeline. Produces `.devteam/plans/<plan-id>/analysis.md` without
implementing or testing anything.

## Usage

```bash
/devteam:analyze --feature "Add OAuth login"
/devteam:analyze --feature "Refactor UserService" --dry-run
```

## Process

Calls `analytics-orchestrator` directly. Skips Stages 2 and 3.

## Output

`analysis.md` with sections:
- Requirements (from `requirements-analyst`)
- Entity Map (from `db-schema-reader`)
- Existing Patterns (from `code-archaeologist`, hybrid only)
- API Contract (from `api-spec-reader`, if OpenAPI/Swagger found)
- Package Layout (used by Stage 2)

## Tips

- Run before `/devteam:build` to inspect the plan
- Use `--dry-run` to see which sub-agents will be invoked
