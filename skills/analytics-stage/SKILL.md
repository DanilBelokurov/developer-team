---
name: analytics-stage
description: "Stage 1 (Analytics) of the Kotlin + Spring backend pipeline. Activates when the pipeline reaches Analytics or when the user requests analysis-only via /devteam:analyze."
priority: 9
---

# Analytics Stage Skill

Coordinates Stage 1 of the Kotlin pipeline: parallel analysis
sub-agents producing `analysis.md`.

## Parallel sub-agents (one assistant turn)

| Agent | When | Output section |
|---|---|---|
| `requirements-analyst` | always | Requirements (ACs, NFRs, user stories) |
| `db-schema-reader` | always | Entity Map |
| `code-archaeologist` | hybrid only | Existing Patterns |
| `api-spec-reader` | OpenAPI/Swagger found | API Contract |

## Predicates

```python
is_hybrid = Path('.git').exists() or any(Path('.').glob('src/main/kotlin/**/*.kt'))
has_spec = any([...openapi/swagger files exist...])
```

## Output

`.devteam/plans/<plan-id>/analysis.md` with:
- Requirements
- Entity Map
- Existing Patterns (if hybrid)
- API Contract (if spec)
- Package Layout (used by Stage 2 partition inference)

## When to use

- Standalone: when the user runs `/devteam:analyze` (planning without
  implementation)
- As Stage 1: invoked by `pipeline-orchestrator`

## Skills to consult

- `requirements-analyst` agent has its own prompt; this skill just
  tells you how to dispatch it
