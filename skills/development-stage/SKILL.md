---
name: development-stage
description: "Stage 2 (Development) of the Kotlin + Spring backend pipeline. Activates when the pipeline reaches Development or when the user requests implementation via /devteam:develop."
priority: 9
---

# Development Stage Skill

Coordinates Stage 2 of the Kotlin pipeline: parallel
implementation sub-agents with disjoint file partitions.

## Pre-condition

Stage 1 (Analytics) must be complete. Read
`.devteam/plans/<plan-id>/analysis.md`.

## Parallel sub-agents (one assistant turn)

| Agent | File partition (Spring conventional) |
|---|---|
| `kotlin-api-developer` | `**/api/`, `**/controller/`, `**/routes/`, `**/dto/` |
| `kotlin-data-architect` | `**/domain/`, `**/entity/`, `**/repository/`, `db/migration/` |
| `kotlin-config-specialist` | `application*.yml`, `logback*.xml`, `gradle.properties` |
| `kotlin-integration-specialist` | `**/client/`, `**/infrastructure/`, `**/event/`, `**/messaging/` |

**Fallback**: if `analysis.md`'s Package Layout section uses
non-standard folder names, inject actual paths. If no layout at all,
fall back to sequential Stage 2 with a single
`kotlin-fullstack-developer` agent.

## Skills reference (passed in each agent's prompt)

- API: `spring-mvc-webflux-api-builder`, `spring-context-di-reasoning`,
  `domain-decomposition-api-design-advisor`,
  `error-model-validation-architect`,
  `jackson-kotlin-serialization-specialist`
- Data: `jpa-spring-data-kotlin-mapper`, `schema-migration-planner`,
  `transaction-consistency-designer`
- Config: `gradle-kotlin-dsl-doctor`,
  `configuration-properties-profiles-kotlin-safe`
- Integration: `integration-resilience-engineer`,
  `jackson-kotlin-serialization-specialist`, `observability-integrator`

## Output

- Code changes in 4 partitions
- `stage2.merge.md` with overlap check (must be "none") and build
  verification (`./gradlew compileKotlin ktlintCheck detekt`)

## When to use

- Standalone: when the user runs `/devteam:develop` (after manual analysis)
- As Stage 2: invoked by `pipeline-orchestrator`
