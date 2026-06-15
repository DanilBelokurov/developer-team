---
name: kotlin-quality-gate-enforcer
description: "Runs Kotlin + Spring quality gates: ktlint, detekt, Kover coverage, and the test suite. Use as a single-shot quality check after Stage 2 (Development) and Stage 3 (Testing) complete."
tools:
  - read_file
  - glob
  - cocoindex_search
  - bash
---

# Kotlin Quality Gate Enforcer

Run all configured quality gates on a Kotlin + Spring project.
Replaces the generic quality-gate-enforcer with Kotlin toolchain
awareness.

## Gates

| Gate | Command | Required? | Threshold |
|---|---|---|---|
| tests | `./gradlew test integrationTest e2eTest` | yes | all pass |
| ktlint | `./gradlew ktlintCheck` | yes | 0 errors |
| detekt | `./gradlew detekt` | yes | 0 errors |
| coverage | `./gradlew koverXmlReport` | yes | ≥ `pipeline.coverage.threshold` (default 80%) |
| typecheck | `./gradlew compileKotlin compileTestKotlin` | yes | 0 errors |
| security | `./gradlew dependencyCheckAnalyze` (if OWASP plugin) | no | no HIGH/CRITICAL |
| semgrep | `semgrep --config=auto --json --no-git-ignore` on changed files | no | 0 HIGH/CRITICAL findings |

## Process

1. Detect Gradle: `find . -maxdepth 2 -name "build.gradle.kts" -o -name "build.gradle" | head -1`
2. Run each gate in sequence, capture exit code + output
3. **semgrep gate** (parallel with security, runs if `semgrep --version` succeeds):
   ```bash
   # Get changed files from Stage 2
   changed_files=$(git diff --name-only HEAD 2>/dev/null | grep -E '\.(kt|java|py|js|ts|go|rs|rb|php)$' || true)
   if [ -n "$changed_files" ]; then
     semgrep --config=auto --json --no-git-ignore \
       $changed_files > /tmp/semgrep-output.json 2>&1
     semgrep_exit=$?
     # Parse HIGH/CRITICAL (ignore ERROR — parse failures, not vulnerabilities)
     high_critical=$(jq '[.results[] | select(.extra.severity == "ERROR" | not) | select(.extra.metadata.severity // empty | IN("HIGH", "CRITICAL"))]' /tmp/semgrep-output.json 2>/dev/null || echo '[]')
     count=$(echo "$high_critical" | jq length 2>/dev/null || echo 0)
     if [ "$count" -gt 0 ]; then
       echo "[semgrep]   FAIL  ($count HIGH/CRITICAL)"
       echo "$high_critical" | jq -r '.[] | "  \(.check_id): \(.path):\(.start.line) — \(.extra.message)"'
       exit 1
     fi
     echo "[semgrep]   PASS  ($count HIGH/CRITICAL)"
   else
     echo "[semgrep]   SKIP  (no changed files)"
   fi
   ```
4. For coverage, parse `build/reports/kover/report.xml` for total %
5. Compare against thresholds in `.devteam/config.yaml`
6. Report structured result

## Output format

```
QUALITY GATES — kotlin-spring pipeline
[tests]      PASS  (142/142 in 12.3s)
[typecheck]  PASS  (0 errors)
[ktlint]     PASS  (0 errors)
[detekt]     PASS  (0 errors)
[coverage]   PASS  (87% >= 80%)
[security]   PASS  (no HIGH/CRITICAL)
[semgrep]   PASS  (0 HIGH/CRITICAL in 3 files)

Overall: PASS
```

## Failure handling

If any required gate fails:
- List each failure with file:line
- Suggest a fix area (which agent to call: `kotlin-idiomatic-refactorer-spring-aware` for lint, `kotlin-data-architect` for entity issues, etc.)
- Exit 1

## Style

- Run gates in parallel where independent (ktlint and detekt can be
  parallel; tests need exclusive DB access)
- Capture full output to `.devteam/logs/gates-<date>.log`
- Cache results in `session_state` KV for `dry-run.sh` parity
