---
name: testing-stage
description: "Stage 3 (Testing) of the Kotlin + Spring backend pipeline. Activates when the pipeline reaches Testing or when the user requests tests via /devteam:test."
priority: 9
---

# Testing Stage Skill

Coordinates Stage 3 of the Kotlin pipeline: parallel test
engineers + quality gates.

## Pre-condition

Stage 2 (Development) must be complete. Code changes are in the
working tree.

## Parallel sub-agents (one assistant turn)

| Agent | Test scope |
|---|---|
| `kotlin-unit-test-engineer` | Unit tests (JUnit 5 + Kotest + MockK) |
| `kotlin-integration-test-engineer` | Integration tests (Spring Boot + Testcontainers) |
| `kotlin-e2e-test-engineer` | E2E + contract tests (REST Assured + WireMock) |

## Quality gate

After all 3 agents complete, dispatch `kotlin-quality-gate-enforcer`:

```bash
./gradlew test integrationTest e2eTest
./gradlew ktlintCheck detekt
./gradlew koverXmlReport   # coverage must be >= pipeline.coverage.threshold
```

If coverage < threshold or any test fails:
- Retry the responsible test engineer (not the whole stage)
- Up to `pipeline.retry.per_agent` times
- Then halt stage with structured report

## Skills reference

- All 3 agents: `test-suite-builder`
- Integration: `integration-resilience-engineer`
- E2E: `integration-resilience-engineer`, `stacktrace-log-triage`

## Output

- Test reports (per framework)
- Coverage report (Kover)
- Quality gate status (ktlint, detekt, OWASP)
- `TASK_COMPLETE` + `EXIT_SIGNAL: true` (if all gates pass)

## When to use

- Standalone: `/devteam:test` (verify existing code)
- As Stage 3: invoked by `pipeline-orchestrator`
