---
name: kotlin-quality-gate
description: "Run all Kotlin + Spring quality gates: tests, ktlint, detekt, Kover coverage, typecheck, OWASP. Use as a single-shot check after Stage 2/3 or for periodic verification."
priority: 5
---

# Kotlin Quality Gate

Run all configured quality gates on a Kotlin + Spring project.
Replaces the generic quality gate with Kotlin toolchain awareness.

## Gates

| Gate | Command | Required | Threshold |
|---|---|---|---|
| tests | `./gradlew test integrationTest e2eTest` | yes | all pass |
| ktlint | `./gradlew ktlintCheck` | yes | 0 errors |
| detekt | `./gradlew detekt` | yes | 0 errors |
| coverage | `./gradlew koverXmlReport` | yes | >= `pipeline.coverage.threshold` (default 80%) |
| typecheck | `./gradlew compileKotlin compileTestKotlin` | yes | 0 errors |
| security | `./gradlew dependencyCheckAnalyze` (if OWASP plugin) | no | no HIGH/CRITICAL |

## Process

1. Detect Gradle build (find `build.gradle.kts` or `build.gradle`)
2. Run each gate, capture exit code + output
3. For coverage, parse `build/reports/kover/report.xml` for total %
4. Compare against thresholds
5. Report structured result

## Output format

```
QUALITY GATES - kotlin-spring pipeline
[tests]      PASS  (142/142 in 12.3s)
[typecheck]  PASS  (0 errors)
[ktlint]     PASS  (0 errors)
[detekt]     PASS  (0 errors)
[coverage]   PASS  (87% >= 80%)
[security]   PASS  (no HIGH/CRITICAL)

Overall: PASS
```

## Failure handling

If any required gate fails:
- List each failure with file:line
- Suggest a fix area (which agent to call: `kotlin-idiomatic-refactorer-spring-aware` for lint, `kotlin-data-architect` for entity issues, etc.)
- Exit 1

## Skills reference

- `kotlin-idiomatic-refactorer-spring-aware` (for ktlint/detekt fixes)
- `gradle-kotlin-dsl-doctor` (for build issues)
