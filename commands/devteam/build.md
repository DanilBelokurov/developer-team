---
description: "Kotlin + Spring backend 3-stage pipeline: Analytics → Development → Testing, with parallel sub-stages. Supports --skip-stage and --dry-run."
argument-hint: --feature "..." [--skip-stage analytics|development|testing] [--simulate-fail-stage=NAME] [--pipeline.retry.per_agent=N]
---

# /devteam:build

**IMMEDIATELY invoke the pipeline-orchestrator agent.**
Do NOT implement anything yourself. Do NOT write code directly.

You MUST call the `agent()` tool with `subagent_type="pipeline-orchestrator"`:

```
agent(subagent_type="pipeline-orchestrator", prompt="/devteam:build --feature \"<feature>\" [--flags]")
```

The pipeline-orchestrator agent handles all logic: dispatching stages,
managing state, and coordinating parallel sub-agents.

Full Kotlin + Spring backend development pipeline. Runs three
sequential stages with parallel sub-agents within each.

## Three stages

1. **Analytics** (parallel) — requirements, DB schema, code review
2. **Development** (parallel) — API, data, config, integration
3. **Testing** (parallel) — unit, integration, e2e

## Usage

```bash
/devteam:build --feature "Add OAuth login with refresh tokens"
/devteam:build --feature "Add /health endpoint" --skip-stage testing
/devteam:build --feature "Add audit log" --skip-stage analytics,development
/devteam:build --feature "X" --dry-run
```

## Argument validation (mirrored in `scripts/dry-run.sh`)

`--skip-stage` accepts:
- A single value: `--skip-stage analytics`
- Comma-separated: `--skip-stage analytics,development`
- Space-separated (quote it): `--skip-stage "analytics development"`

Valid values: `analytics`, `development`, `testing`.

**Errors**:
- `--skip-stage` without a value → `ERROR: --skip-stage requires an argument`
- Unknown value (e.g., `--skip-stage banana`) → `ERROR: --skip-stage 'banana' is not one of: analytics development testing`
- Duplicate value → `ERROR: --skip-stage '<value>' specified twice`

## Flags

- `--feature "..."` — **required** feature description
- `--skip-stage X,Y` — skip named stages (repeatable via comma)
- `--simulate-fail-stage=NAME` — for dry-run testing of failure paths
- `--pipeline.retry.per_agent=N` — override default retry count (default 2)
- `--dry-run` — print the planned dispatch sequence without invoking
  agents; for verification
- `--simulate-hitl-approve` | `reject` | `edit` | `abort` — for testing
  the Human-in-the-Loop gate (see HITL section below)

## Process

### 0. Initialize

```bash
source "$QWEN_PROJECT_DIR/scripts/state.sh"

# Generate slug from feature name: "Add OAuth login" -> "add-oauth-login"
SLUG=$(echo "$FEATURE" | sed 's/[^a-zA-Z0-9 ]//g' | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | cut -c1-30)
PLAN_ID="plan-${SLUG}-$(date +%Y%m%d)-$(uuidgen | cut -c1-8)"
mkdir -p ".devteam/plans/$PLAN_ID"
set_kv_state "pipeline.active" "true" "$PLAN_ID"
set_kv_state "pipeline.feature" "$FEATURE" "$PLAN_ID"
set_kv_state "pipeline.plan_id" "$PLAN_ID" "$PLAN_ID"
```

### 1. Compute predicates (BEFORE dry-run output)

```python
is_hybrid_predicate = Path('.git').exists() or any(Path('.').glob('src/main/kotlin/**/*.kt'))
has_api_spec = any([
    Path('**/openapi.yml'),
    Path('**/openapi.yaml'),
    Path('**/openapi.json'),
    Path('**/swagger.yml'),
    Path('**/swagger.yaml'),
    Path('**/swagger.json'),
])
```

### 2. Stage 1 — Analytics (if not skipped)

Call `analytics-orchestrator` (which dispatches parallel sub-agents).
Skip if `--skip-stage analytics` was passed.

Sub-agents invoked in **one assistant turn** (true parallelism):

- `requirements-analyst` (always)
- `db-schema-reader` (always)
- `code-archaeologist` (only if `is_hybrid_predicate`)
- `api-spec-reader` (only if `has_api_spec`)

All four (or fewer) calls happen in the same `agent()` invocation
block. Do NOT chain them sequentially.

### 3. Stage 2 — Development (if not skipped)

Call `development-orchestrator` with the `analysis.md` from Stage 1.
Skip if `--skip-stage development` was passed.

Sub-agents invoked in one assistant turn (parallel). Each owns a
disjoint file partition (see `agents/development-orchestrator.md`):

- `kotlin-api-developer` (owns `**/api/`, `**/controller/`, `**/routes/`, `**/dto/`)
- `kotlin-data-architect` (owns `**/domain/`, `**/entity/`, `**/repository/`, `db/migration/`)
- `kotlin-config-specialist` (owns `application*.yml`, `logback*.xml`, `gradle.properties`)
- `kotlin-integration-specialist` (owns `**/client/`, `**/infrastructure/`, `**/event/`, `**/messaging/`)

After all four complete, the orchestrator writes `stage2.merge.md`
with overlap check (must be "none") and build verification. If
overlap detected → halt stage, emit structured report.

**Fallback for non-conforming package layout**: if `analysis.md`'s
Package Layout section uses non-standard folder names, the orchestrator
injects the actual paths into each agent's prompt. If no
recognizable layout at all, fall back to **sequential** Stage 2 with
a single `kotlin-fullstack-developer` agent.

### 4. Stage 3 — Testing (if not skipped)

Call `testing-orchestrator`. Skip if `--skip-stage testing` was
passed.

Sub-agents invoked in one assistant turn (parallel):

- `kotlin-unit-test-engineer` (owns unit tests)
- `kotlin-integration-test-engineer` (owns integration tests + Testcontainers)
- `kotlin-e2e-test-engineer` (owns e2e + contract tests)

After all three complete, run `kotlin-quality-gate-enforcer`:
- `./gradlew test integrationTest e2eTest`
- `./gradlew ktlintCheck detekt`
- `./gradlew koverXmlReport` (coverage ≥ 80%)

If coverage < threshold OR any test fails: retry the responsible
test engineer (not the whole stage) up to
`pipeline.retry.per_agent` times, then halt stage.

### 5. Failure policy

Per-agent retry up to `pipeline.retry.per_agent` (default 2). After
max retries, halt stage and emit:

```text
STAGE 2 FAILED
Failed agents (retries exhausted):
  - kotlin-data-architect: 2/2 retries. Last error: <error>
Succeeded agents (output preserved):
  - kotlin-api-developer: 12 files
  - kotlin-config-specialist: 1 file
  - kotlin-integration-specialist: 3 files
```

Configurable in `.devteam/config.yaml`:
```yaml
pipeline:
  retry:
    per_agent: 2
    on_failure: halt_stage  # or skip_failed_agent, halt_pipeline
```

### 6. Completion

When all stages complete (or are skipped), emit:

```text
TASK_COMPLETE: pipeline-<plan-id>
EXIT_SIGNAL: true
```

The Stop hook will allow session exit only when this is present.

## Human-in-the-Loop (HITL) gate

After Stage 1 (Analytics) completes, the pipeline **pauses** for
your approval before Stage 2 (Development) starts. This is
**always-on** for `/devteam:build` (production safety).

The orchestrator calls `ask_user_question` with 4 options:

- **Approve and continue to Stage 2** — analysis.md looks good
- **Request changes (re-run Stage 1)** — analysis needs work; pipeline
  re-runs Analytics with refined input
- **Edit analysis.md manually, then continue** — you fix the file,
  pipeline continues
- **Abort pipeline** — stop here, no further stages

### State

The HITL pause is recorded in `.devteam/devteam.db`:

```sql
SELECT value FROM session_state WHERE key = 'stage.development.status';
-- "awaiting_approval" | "pending" | "completed" | ...

SELECT value FROM session_state WHERE key = 'stage.development.hitl_action';
-- "approve" | "edit" | "request_changes" | "abort"
```

### Skip HITL

HITL is **automatically skipped** when:
- `--skip-stage development` is passed (no Stage 2 → no approval needed)
- `--skip-stage analytics,development` is passed
- Stage 1 produced no analysis.md (failed or empty)

### Resume from paused state

If Qwen Code restarts while HITL is paused (session crash, user
break), the pipeline detects the paused state on next run. The
orchestrator reads `stage.development.hitl_action` from KV:
- `approve` / `edit` → resume Stage 2 (status → pending)
- `request_changes` → re-run Stage 1
- `abort` → manual intervention required

To manually clear a paused state:

```bash
/devteam:reset --circuit
```

## Tips

- Use `--dry-run` first to verify the dispatch sequence
- Use `--skip-stage analytics` after manual planning (analysis.md exists)
- Use `--skip-stage development testing` to only run analytics
- Use `--simulate-fail-stage=development` to test the failure report format
- Use `--simulate-hitl-approve|reject|edit|abort` to test the HITL flow
- HITL pauses every `/devteam:build` after Stage 1 — expect to
  interact with the prompt
