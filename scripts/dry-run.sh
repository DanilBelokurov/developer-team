#!/bin/bash
# dry-run.sh — Shell mirror of the /devteam:build pipeline-orchestrator.
# Prints the planned agent dispatch sequence without invoking agents.
# Used for V5/V5b/V6/V6b/V7/V8/V9/V9b verifications.
#
# Usage:
#   scripts/dry-run.sh --feature "Add OAuth" [--skip-stage X,Y]
#                        [--pipeline.retry.per_agent=N]
#                        [--simulate-fail-stage=NAME]
#
# Stages: analytics | development | testing
set -euo pipefail

FEATURE=""
SKIP=()
RETRY=2
SIMULATE_FAIL=""

# Argument parsing
while [ $# -gt 0 ]; do
  case "$1" in
    --feature)
      [ $# -ge 2 ] || { echo "ERROR: --feature requires an argument"; exit 2; }
      FEATURE="$2"; shift 2;;
    --skip-stage)
      [ $# -ge 2 ] || { echo "ERROR: --skip-stage requires an argument"; exit 2; }
      # Support both comma-separated (--skip-stage analytics,development)
      # and space-separated (--skip-stage "analytics development").
      # Space-separated requires the user to quote the value.
      raw="$2"
      # Replace spaces with commas so we can use a single split
      raw_csv=$(echo "$raw" | tr ' ' ',')
      IFS=',' read -ra stages <<< "$raw_csv"
      for s in "${stages[@]}"; do
        [ -z "$s" ] && continue
        case "$s" in
          analytics|development|testing) ;;
          *) echo "ERROR: --skip-stage '$s' is not one of: analytics development testing"; exit 2;;
        esac
        for existing in "${SKIP[@]:-}"; do
          [ "$s" = "$existing" ] && { echo "ERROR: --skip-stage '$s' specified twice"; exit 2; }
        done
        SKIP+=("$s")
      done
      shift 2;;
    --pipeline.retry.per_agent=*)
      RETRY="${1#*=}"
      case "$RETRY" in
        ''|*[!0-9]*) echo "ERROR: --pipeline.retry.per_agent must be a positive integer"; exit 2;;
      esac
      shift;;
    --simulate-fail-stage=*)
      SIMULATE_FAIL="${1#*=}"
      shift;;
    *) echo "ERROR: unknown argument: $1"; exit 2;;
  esac
done

if [ -z "$FEATURE" ]; then
  echo "ERROR: --feature is required"
  exit 2
fi

is_skipped() {
  local stage="$1"
  for s in "${SKIP[@]:-}"; do
    [ "$s" = "$stage" ] && return 0
  done
  return 1
}

# Predicates (mirror of build.md logic)
HYBRID=false
if [ -d .git ]; then HYBRID=true; fi
if find . -path ./vendors -prune -o -name "*.kt" -print 2>/dev/null | grep -q .; then HYBRID=true; fi

HAS_SPEC=false
for f in $(find . -path ./vendors -prune -o \( -name "openapi.yml" -o -name "openapi.yaml" -o -name "openapi.json" -o -name "swagger.yml" -o -name "swagger.yaml" -o -name "swagger.json" \) -print 2>/dev/null); do
  HAS_SPEC=true
  break
done

CODE_ARCH_STATUS="SKIPPED"
[ "$HYBRID" = "true" ] && CODE_ARCH_STATUS="INCLUDED"
SPEC_STATUS="SKIPPED"
[ "$HAS_SPEC" = "true" ] && SPEC_STATUS="INCLUDED"

# Print
echo "DRY-RUN: /devteam:build --feature \"$FEATURE\""
[ ${#SKIP[@]} -gt 0 ] && echo "         --skip-stage $(IFS=,; echo "${SKIP[*]}")"
echo ""

# Stage 0
echo "Stage 0: Initialize"
echo "  -> set session_state: stage.analytics.status = \"pending\""
echo "  -> set session_state: stage.development.status = \"pending\""
echo "  -> set session_state: stage.testing.status = \"pending\""
echo ""

# Stage 1
if is_skipped analytics; then
  echo "Stage 1: Analytics (SKIPPED via --skip-stage analytics)"
  echo ""
elif [ "$SIMULATE_FAIL" = "analytics" ]; then
  echo "Stage 1: Analytics (SIMULATED FAILURE)"
  echo "  -> agent(requirements-analyst, prompt=\"...$FEATURE...\")"
  echo ""
  echo "STAGE 1 FAILED"
  echo "Failed agents (retries exhausted):"
  echo "  - requirements-analyst: 2/2 retries. Last error: simulated failure"
  echo "Succeeded agents (output preserved):"
  echo "  - (none)"
  echo ""
  echo "Retry policy: per_agent=$RETRY, on_failure=halt_stage"
  echo "EXIT_SIGNAL: true"
  exit 0
else
  echo "Stage 1: Analytics (parallel)"
  echo "  Predicate is_hybrid_predicate: $HYBRID -> code-archaeologist $CODE_ARCH_STATUS"
  echo "  Predicate has_api_spec: $HAS_SPEC -> api-spec-reader $SPEC_STATUS"
  echo "  -> agent(requirements-analyst, prompt=\"...$FEATURE...\")"
  echo "  -> agent(db-schema-reader, prompt=\"...$FEATURE...\")"
  [ "$HYBRID" = "true" ] && echo "  -> agent(code-archaeologist, prompt=\"...$FEATURE...\")"
  [ "$HAS_SPEC" = "true" ] && echo "  -> agent(api-spec-reader, prompt=\"...$FEATURE...\")"
  echo "  -> set session_state: stage.analytics.status = \"completed\""
  echo ""
fi

# Stage 2
if is_skipped development; then
  echo "Stage 2: Development (SKIPPED via --skip-stage development)"
  echo ""
elif [ "$SIMULATE_FAIL" = "development" ]; then
  echo "Stage 2: Development (parallel, file partition, SIMULATED FAILURE)"
  echo "  -> agent(kotlin-api-developer) — owns: **/api/, **/controller/, **/routes/, **/dto/"
  echo "  -> agent(kotlin-data-architect) — owns: **/domain/, **/entity/, **/repository/, db/migration/"
  echo "  -> agent(kotlin-config-specialist) — owns: application*.yml, logback*.xml"
  echo "  -> agent(kotlin-integration-specialist) — owns: **/client/, **/infrastructure/, **/event/"
  echo "  Overlaps: none"
  echo ""
  echo "STAGE 2 FAILED"
  echo "Failed agents (retries exhausted):"
  echo "  - kotlin-data-architect: 2/2 retries. Last error: simulated failure"
  echo "Succeeded agents (output preserved):"
  echo "  - kotlin-api-developer: 12 files"
  echo "  - kotlin-config-specialist: 1 file"
  echo "  - kotlin-integration-specialist: 3 files"
  echo ""
  echo "Retry policy: per_agent=$RETRY, on_failure=halt_stage"
  echo "EXIT_SIGNAL: true"
  exit 0
else
  echo "Stage 2: Development (parallel, file partition)"
  echo "  -> agent(kotlin-api-developer) — owns: **/api/, **/controller/, **/routes/, **/dto/"
  echo "  -> agent(kotlin-data-architect) — owns: **/domain/, **/entity/, **/repository/, db/migration/"
  echo "  -> agent(kotlin-config-specialist) — owns: application*.yml, logback*.xml"
  echo "  -> agent(kotlin-integration-specialist) — owns: **/client/, **/infrastructure/, **/event/"
  echo "  Overlaps: none"
  echo "  -> set session_state: stage.development.status = \"completed\""
  echo ""
fi

# Stage 3
if is_skipped testing; then
  echo "Stage 3: Testing (SKIPPED via --skip-stage testing)"
elif [ "$SIMULATE_FAIL" = "testing" ]; then
  echo "Stage 3: Testing (parallel, SIMULATED FAILURE)"
  echo "  -> agent(kotlin-unit-test-engineer, prompt=\"...\")"
  echo "  -> agent(kotlin-integration-test-engineer, prompt=\"...\")"
  echo "  -> agent(kotlin-e2e-test-engineer, prompt=\"...\")"
  echo ""
  echo "STAGE 3 FAILED"
  echo "Failed agents (retries exhausted):"
  echo "  - kotlin-integration-test-engineer: 2/2 retries. Last error: simulated failure"
  echo "Succeeded agents (output preserved):"
  echo "  - kotlin-unit-test-engineer: tests pass"
  echo "  - kotlin-e2e-test-engineer: tests pass"
  echo ""
  echo "Retry policy: per_agent=$RETRY, on_failure=halt_stage"
  echo "EXIT_SIGNAL: true"
  exit 0
else
  echo "Stage 3: Testing (parallel)"
  echo "  -> agent(kotlin-unit-test-engineer, prompt=\"...\")"
  echo "  -> agent(kotlin-integration-test-engineer, prompt=\"...\")"
  echo "  -> agent(kotlin-e2e-test-engineer, prompt=\"...\")"
  echo "  -> set session_state: stage.testing.status = \"completed\""
fi

echo ""
echo "Retry policy: per_agent=$RETRY, on_failure=halt_stage"
echo "EXIT_SIGNAL: true"
