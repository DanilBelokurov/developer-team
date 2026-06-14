---
description: "Run only Stage 3 (Testing) of the Kotlin pipeline. Dispatches parallel test engineers and runs quality gates. Requires Stage 2 to be complete."
argument-hint: [--feature "..."] [--plan-id <id>] [--dry-run]
---

# /devteam:test

Run only the Testing stage of the Kotlin + Spring backend
pipeline. Dispatches parallel test engineers and runs the
`kotlin-quality-gate-enforcer`.

## Pre-condition

`/devteam:develop` (or equivalent) must have produced code changes.
The orchestrator runs tests against the current working directory.

## Usage

```bash
/devteam:test
/devteam:test --feature "Add OAuth login"
/devteam:test --plan-id plan-20260613-143022-a3f9
/devteam:test --dry-run
```

## Process

Calls `testing-orchestrator` directly. Skips Stages 1 and 2.

## Output

Test reports + coverage:
- Unit test results (JUnit 5 + Kotest + MockK)
- Integration test results (Spring Boot + Testcontainers)
- E2E test results (REST Assured + WireMock)
- Kover coverage (must be >= `pipeline.coverage.threshold`)
- ktlint / detekt status
- OWASP dependency check (if configured)

## Tips

- Run after `/devteam:develop` or `/devteam:build --skip-stage testing`
- Coverage threshold configurable in `.devteam/config.yaml`
