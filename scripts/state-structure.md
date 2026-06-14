# DevTeam State Structure (v6.2)

**Document**: Describes the file-based state layout in `.devteam/state/`.
**Replaces**: `scripts/schema.sql` (v6.1 SQLite schema, archived).
**Created by**: `scripts/state-init.sh`
**Read by**: `scripts/state.sh` and hooks (via `source state.sh`)

---

## Overview

All runtime state is stored as Markdown files in `.devteam/state/`.
No external binary requirements (no `sqlite3`, no `psql`, etc.). Works
on macOS, Linux, Windows. Human-readable, git-diffable, editable in
any IDE.

Atomic writes via mkdir-based locking (POSIX-portable).

---

## Directory layout

```
.devteam/
└── state/
    ├── current-session.md              # pointer to active session ("session/<id>")
    ├── sessions/
    │   └── session-YYYYMMDD-HHMMSS-<rand>.md
    ├── kv/
    │   └── <key>                       # one file per KV key (e.g. stage.analytics.status)
    ├── events/
    │   └── YYYY-MM-DD-events.md        # append-only daily log
    ├── agent-runs/
    │   └── run-YYYYMMDD-HHMMSS-<rand>.md
    ├── tasks/
    │   └── TASK-NNN.md
    ├── circuit-breaker.md              # circuit breaker state (YAML frontmatter)
    └── gates.md                        # quality gate log (append-only)
```

---

## File formats

### `current-session.md`

Plain text, one line:

```
session/session-20260614-161835-3f145341
```

Set by `start_session()`, cleared/updated by `end_session()`.

---

### `sessions/<id>.md`

YAML frontmatter + Markdown body. Parsed by `get_frontmatter_value()`.

```markdown
---
id: session-20260614-161835-3f145341
started_at: 2026-06-14T16:18:35Z
ended_at: ~
command: /devteam:build --feature "Add OAuth login"
command_type: build
status: running
current_phase: executing
current_iteration: 4
max_iterations: 10
consecutive_failures: 0
circuit_breaker_state: closed
execution_mode: normal
total_tokens_input: 1000
total_tokens_output: 500
total_cost_cents: 10
bug_council_activated: FALSE
bug_council_reason: ~
---

# Session session-20260614-161835-3f145341

## State
- pipeline.active: true
- stage.analytics.status: completed
- stage.development.status: awaiting_approval
- hitl_action: approve

## Activity
- 16:18:35 [start] command received
- 16:20:00 [stage 1] agent_invoked requirements-analyst
- 16:22:00 [stage 1] status=completed
- 16:22:00 [hitl] paused for approval
```

**Frontmatter fields** (machine-parseable, set by `set_state()`):

| Field | Type | Description |
|---|---|---|
| `id` | string | Unique session ID |
| `started_at` | ISO 8601 | Session start timestamp |
| `ended_at` | ISO 8601 / `~` | End timestamp (or `~` if running) |
| `command` | string | Full command line |
| `command_type` | enum | `build`, `analyze`, `develop`, `test`, `review`, `bug`, etc. |
| `status` | enum | `running`, `completed`, `failed`, `aborted` |
| `current_phase` | string | Free-form phase name |
| `current_iteration` | int | Loop iteration counter |
| `max_iterations` | int | Loop max (default 10) |
| `consecutive_failures` | int | Failure counter for circuit breaker |
| `circuit_breaker_state` | enum | `closed`, `open`, `half-open` |
| `execution_mode` | enum | `normal`, `eco` |
| `total_tokens_input` | int | Cost tracking |
| `total_tokens_output` | int | Cost tracking |
| `total_cost_cents` | int | Cost tracking |
| `bug_council_activated` | bool | TRUE / FALSE |
| `bug_council_reason` | string | Reason for activation |

**Body** (human-readable): free-form Markdown with `## State` and
`## Activity` sections. Activity is append-only log.

---

### `kv/<key>`

Plain text, one value per file. Examples:

```bash
$ cat .devteam/state/kv/stage.analytics.status
completed
$ cat .devteam/state/kv/stage.development.hitl_action
approve
$ cat .devteam/state/kv/pipeline.retry_counts
{"kotlin-data-architect": 2}
```

**Key naming convention**: `<scope>.<key>` (dot-separated). Examples:
- `stage.analytics.status`
- `stage.development.hitl_action`
- `pipeline.active`
- `pipeline.feature`

**Value**: any UTF-8 string. For complex data, use JSON. For
booleans, use `true` / `false`. For "null", use `~`.

**Atomic writes**: `set_kv_state()` uses mkdir-based locking. Lock
directory is at `<key>.lock` (sibling to the key file).

---

### `events/<date>-events.md`

Append-only log, one file per day. Never edit, only append.

```markdown
# Events 2026-06-14

## 16:18:35 — session_started
- session_id: session-20260614-161835-3f145341
- command: /devteam:build
- command_type: build

## 16:20:00 — agent_invoked
- session_id: session-20260614-161835-3f145341
- agent: requirements-analyst
- model: sonnet
- iteration: 1

## 16:22:00 — stage_completed
- session_id: session-20260614-161835-3f145341
- stage: analytics
- duration_seconds: 156
```

**Event types** (50+):
`session_started`, `session_ended`, `phase_changed`, `agent_started`,
`agent_completed`, `agent_failed`, `model_escalated`, `model_deescalated`,
`gate_passed`, `gate_failed`, `bug_council_activated`, `bug_council_completed`,
`hitl_paused`, `hitl_resolved`, `error_occurred`, `warning_issued`,
`abandonment_detected`, `abandonment_prevented`, ...

---

### `agent-runs/<run-id>.md`

YAML frontmatter + body. One file per agent invocation.

```markdown
---
run_id: run-20260614-162000-a3f9
session_id: session-20260614-161835-3f145341
agent: requirements-analyst
agent_type: orchestration
model: sonnet
started_at: 2026-06-14T16:20:00Z
ended_at: 2026-06-14T16:21:30Z
duration_seconds: 90
status: success
iteration: 1
task_id: ~
---

# Agent run: requirements-analyst

## Input
- feature: "Add OAuth login with refresh tokens"
- stage: analytics

## Output (summary)
Created analysis.md section "Requirements" with 4 ACs.

## Tokens
- input: 4521
- output: 8934
- cost_cents: 23
```

---

### `tasks/<TASK-ID>.md`

YAML frontmatter + body. One file per task.

```markdown
---
task_id: TASK-001
session_id: session-20260614-161835-3f145341
plan_id: plan-20260614-161835-3f145341
sprint_id: SPRINT-001
parent_task_id: ~
---

# Task TASK-001

## Metadata
- title: Add /health endpoint
- description: Health check returning 200 OK with timestamp
- status: completed
- agent_type: kotlin-api-developer
- complexity_score: 3
- iterations_used: 1

## Scope
### Allowed patterns
- src/main/kotlin/**/api/**
- src/main/kotlin/**/controller/**

### Forbidden patterns
- src/main/kotlin/**/entity/**

## Acceptance criteria
- [x] AC-1: GET /health returns 200 OK
- [x] AC-2: Response body includes timestamp
```

---

### `circuit-breaker.md`

YAML frontmatter only. Updated in-place.

```markdown
---
state: closed
consecutive_failures: 0
max_consecutive_failures: 5
last_failure_at: ~
last_success_at: 2026-06-14T16:21:30Z
opened_at: ~
half_open_at: ~
---
```

State transitions:
- `closed` → `open` (when consecutive_failures >= max)
- `open` → `half-open` (after timeout)
- `half-open` → `closed` (on first success) or `open` (on failure)

---

### `gates.md`

Append-only log (one file, all gates).

```markdown
# Quality Gates

## 16:25:00 — gate: tests
- session_id: session-20260614-161835-3f145341
- task_id: ~
- status: pass
- duration_ms: 12300
- command: ./gradlew test
- output_excerpt: "142 tests completed, 0 failed"

## 16:25:30 — gate: ktlint
- session_id: session-20260614-161835-3f145341
- status: fail
- duration_ms: 4500
- errors:
  - src/main/kotlin/.../oauth.py:42:1
```

---

## Concurrency model

**Locking strategy**: mkdir-based. Each `set_kv_state()`,
`atomic_write()`, etc. creates a sidecar `<file>.lock` directory. mkdir
returns `EEXIST` if it already exists (atomic on POSIX). We spin with
a small backoff (10ms) up to 100 retries (~1s timeout).

**Why not `flock`**: not available on macOS by default. mkdir-based
locking is POSIX-portable and works everywhere.

**Concurrency scope**:
- Multiple hooks firing simultaneously (rare, e.g., session restart)
- LLM orchestrator running sub-agents in parallel (writes to events)
- User typing in another terminal (reads only)

**Not a concern** (sequential by design):
- `start_session()` / `end_session()` (single-threaded)
- Pipeline orchestrator (LLM-driven, sequential)

---

## Backward compat with v6.1

If upgrading from v6.1 with existing `.devteam/devteam.db`:

1. **Recommended**: Run `scripts/state-migrate-v61-to-v62.sh` (one-time
   conversion script provided).
2. **Alternative**: Delete `.devteam/devteam.db` and start fresh.

After migration or fresh start:
- All function signatures in `state.sh` are unchanged (`set_kv_state`,
  `get_kv_state`, `set_state`, `get_state`, `start_session`, etc.)
- Hooks and orchestrator code that source `state.sh` continue to
  work without modification.
- v6.1 schema files archived at `legacy/claude-code/sqlite-schema/`.

---

## Why not SQLite?

- **No external binary requirement** — works on any system
- **Human-readable** — `cat` the file, edit in any IDE
- **Git-trackable** — diff state changes in PRs
- **Trivial backup** — `cp -r .devteam/state backup/`
- **Zero dependencies** — pure POSIX shell

Trade-offs accepted:
- Slower for high-frequency reads (file I/O vs indexed queries)
- No SQL query power (use `grep` / `awk`)
- No transactional semantics (use mkdir-based locking)
- No concurrent writers (use locks; concurrent readers are fine)

For DevTeam's scale (a few sessions per day per project), these
trade-offs are negligible. The benefits dominate.

---

## v6.1 → v6.2 migration helper

`scripts/state-migrate-v61-to-v62.sh` (one-time conversion):

```bash
#!/bin/bash
# Convert .devteam/devteam.db (SQLite) to .devteam/state/ (MD files)
set -euo pipefail

if [ ! -f ".devteam/devteam.db" ]; then
    echo "No legacy DB found"
    exit 0
fi

# Initialize new state structure
bash scripts/state-init.sh .

# Migrate sessions
sqlite3 .devteam/devteam.db ".schema sessions" | head -1  # verify
sqlite3 .devteam/devteam.db "SELECT id, started_at, ended_at, command, command_type, status, current_phase, current_iteration, max_iterations, consecutive_failures, circuit_breaker_state, execution_mode, total_tokens_input, total_tokens_output, total_cost_cents FROM sessions;" | \
while IFS='|' read -r id started_at ended_at command command_type status phase iter max_iter fails cb mode tokens_in tokens_out cost; do
    [[ -z "$id" ]] && continue
    body=$(cat <<EOF
---
id: $id
started_at: $started_at
ended_at: $ended_at
command: $command
command_type: $command_type
status: $status
current_phase: $phase
current_iteration: ${iter:-0}
max_iterations: ${max_iter:-10}
consecutive_failures: ${fails:-0}
circuit_breaker_state: $cb
execution_mode: ${mode:-normal}
total_tokens_input: ${tokens_in:-0}
total_tokens_output: ${tokens_out:-0}
total_cost_cents: ${cost:-0}
bug_council_activated: FALSE
bug_council_reason: ~
---

# Session $id (migrated from v6.1)
EOF
)
    atomic_write ".devteam/state/sessions/$id.md" "$body"
done

# Migrate session_state KV
sqlite3 .devteam/devteam.db "SELECT key, value FROM session_state;" | \
while IFS='|' read -r key value; do
    [[ -z "$key" ]] && continue
    atomic_write ".devteam/state/kv/$key" "$value"
done

# Migrate events to per-day files
sqlite3 .devteam/devteam.db "SELECT timestamp, event_type, session_id, agent, model, iteration, duration_ms, data FROM events ORDER BY timestamp;" | \
while IFS='|' read -r ts event_type session_id agent model iter dur data; do
    [[ -z "$ts" ]] && continue
    day=$(echo "$ts" | cut -c1-10)
    atomic_append ".devteam/state/events/${day}-events.md" "## ${ts} — ${event_type}
- session_id: ${session_id}
- agent: ${agent}
- model: ${model}
- iteration: ${iter}
- duration_ms: ${dur}
- data: ${data}"
done

# Migrate agent_runs
sqlite3 .devteam/devteam.db "SELECT id, session_id, agent, agent_type, model, started_at, ended_at, duration_seconds, status, error_message, task_id, iteration, attempt, tokens_input, tokens_output, cost_cents FROM agent_runs;" | \
while IFS='|' read -r id session_id agent agent_type model started_at ended_at dur status error task_id iter attempt tokens_in tokens_out cost; do
    [[ -z "$id" ]] && continue
    body=$(cat <<EOF
---
run_id: $id
session_id: $session_id
agent: $agent
agent_type: ${agent_type}
model: $model
started_at: $started_at
ended_at: $ended_at
duration_seconds: ${dur}
status: $status
error_message: ${error}
task_id: ${task_id}
iteration: ${iter}
attempt: ${attempt:-1}
tokens_input: ${tokens_in:-0}
tokens_output: ${tokens_out:-0}
cost_cents: ${cost:-0}
---

# Agent run: $agent (migrated from v6.1)
EOF
)
    atomic_write ".devteam/state/agent-runs/$id.md" "$body"
done

# Migrate tasks
sqlite3 .devteam/devteam.db "SELECT id, session_id, plan_id, sprint_id, parent_task_id FROM tasks;" | \
while IFS='|' read -r id session_id plan_id sprint_id parent; do
    [[ -z "$id" ]] && continue
    mkdir -p ".devteam/state/tasks"
    cat > ".devteam/state/tasks/$id.md" <<EOF
---
task_id: $id
session_id: $session_id
plan_id: ${plan_id}
sprint_id: ${sprint_id}
parent_task_id: ${parent}
---

# Task $id (migrated from v6.1)
EOF
done

# Back up legacy DB
mv .devteam/devteam.db .devteam/devteam.db.v61-bak

echo "Migration complete. Original DB at .devteam/devteam.db.v61-bak"
```

---

## File operation API (scripts/state.sh)

All public functions in `state.sh` (35 total, full backward compat):

### Session management
- `generate_session_id` — produces `session-YYYYMMDD-HHMMSS-<rand>`
- `start_session <cmd> <type> [mode]` — creates MD file, returns ID
- `end_session [status] [reason]` — updates frontmatter
- `get_current_session_id` — reads `current-session.md`
- `is_session_running` — checks `status == "running"`
- `get_session_json [id]` — renders frontmatter as JSON (compat)

### KV state
- `set_kv_state <key> <value>` — atomic write with lock
- `get_kv_state <key> [default]` — read
- `delete_kv_state <key>` — remove

### State setters/getters (session frontmatter)
- `set_state <field> <value>` — update frontmatter atomically
- `get_state <field> [default]` — read frontmatter value
- `set_phase <phase>`, `get_current_phase`
- `set_current_agent <agent>`, `get_current_agent`
- `set_current_model <model>`, `get_current_model`
- `get_current_iteration`, `get_consecutive_failures`
- `get_execution_mode`, `is_eco_mode`
- `is_bug_council_active`

### Iteration / failure tracking
- `increment_iteration` — atomic +1
- `increment_failures` — atomic +1
- `reset_failures` — set to 0
- `is_max_iterations_reached`

### Circuit breaker
- `get_circuit_breaker_state` — read state/circuit-breaker.md
- `set_circuit_breaker_state <state>` — atomic update
- `should_trip_circuit_breaker` — check threshold
- `trip_circuit_breaker` — set open
- `reset_circuit_breaker` — set closed

### Model escalation
- `get_next_model <current>`, `get_previous_model <current>` — tier nav
- `record_escalation <from> <to> <reason>` — append event

### Bug council
- `activate_bug_council <reason>` — sets flag + logs event

### Tokens & cost
- `add_tokens <input> <output>` — increments totals + cost
- `get_total_cost_dollars` — formatted dollar amount

### Plans & sprints
- `set_active_plan <id>`, `set_active_sprint <id>` — KV state

### Session summary
- `get_session_summary [id]` — formatted MD
- `get_model_usage` — aggregate from agent-runs/
- `abort_session [reason]`
- `ensure_state_dir` — idempotent init
- `warn_legacy_db` — warning if v6.1 .db present

All 35 function signatures are **unchanged from v6.1**.
