# DevTeam Architecture (v6.0.0+)

**Document**: full architecture description of the Qwen Code extension `devteam`.
**Version**: 6.0.0 (Kotlin + Spring backend pipeline, June 2026).
**Audience**: developers, contributors, users wanting to understand the internals.

---

## Table of Contents

1. [Introduction and scope](#1-introduction-and-scope)
2. [High-level architecture](#2-high-level-architecture)
3. [Deployment context in Qwen Code](#3-deployment-context-in-qwen-code)
4. [Architectural layers](#4-architectural-layers)
5. [Pipeline: 3-stage with parallel sub-agents](#5-pipeline-3-stage-with-parallel-sub-agents)
6. [Failure handling and retry policy](#6-failure-handling-and-retry-policy)
7. [Stage tracking via session_state KV](#7-stage-tracking-via-session_state-kv)
8. [Hook events](#8-hook-events)
9. [Data model (SQLite)](#9-data-model-sqlite)
10. [State machine](#10-state-machine)
11. [Migration from v5.0.0](#11-migration-from-v500)
12. [Extension points — how to add components](#12-extension-points--how-to-add-components)
13. [Design decisions and trade-offs](#13-design-decisions-and-trade-offs)
14. [Limitations and known issues](#14-limitations-and-known-issues)
15. [Glossary](#15-glossary)
16. [File map](#16-file-map)
17. [Sequence: a full pipeline run](#17-sequence-a-full-pipeline-run)

---

## 1. Introduction and scope

**DevTeam** is a Qwen Code extension for autonomous Kotlin + Spring
backend development. It implements a full **3-stage pipeline**
(Analytics → Development → Testing) with **parallel sub-agents**
within each stage.

### Key principles

1. **Qwen Code is the runtime.** The LLM session itself plays the
   orchestrator role (reads slash commands, dispatches subagents via
   `agent()` tool, reacts to hooks). No separate orchestrator process
   exists.

2. **Declarative subagents.** Subagents are Markdown files with a
   system prompt. Qwen Code reads them and invokes via
   `agent({ subagent_type: "..." })`.

3. **Skills are model-invoked.** Each `SKILL.md` in `skills/<name>/`
   is a specialized instruction set the model can activate when the
   description matches the context.

4. **Parallelism within stages, gates between stages.** All
   sub-agents within a stage run in **one assistant turn** (true
   parallelism). Quality gates (`kotlin-quality-gate-enforcer`)
   sit between stages.

5. **Idempotent install.** Installing the extension is idempotent via a
   sentinel file at `<target>/.devteam-installed`. Supports project-level
   (`<project>/.qwen/`) and user-level (`~/.qwen/`) installs.

6. **Upstream skill integration.** Skills from
   [yalishevant/kotlin-backend-agent-skills](https://github.com/yalishevant/kotlin-backend-agent-skills)
   are vendored as a git submodule and synced into `skills/<name>/SKILL.md`.

### What is NOT in scope

- Custom LLM engine (uses Qwen Code)
- Multi-machine orchestration
- Real-time collaboration
- Self-planning without LLM

---

## 2. High-level architecture

```
┌──────────────────────────────────────────────────────────────────┐
│ Qwen Code Session                                                │
│                                                                  │
│  System prompt                                                   │
│  + QWEN.md (auto-loaded, 84 lines)                               │
│  + extension context (skills, agents, commands)                  │
└──────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│ User input ──→ /devteam:build --feature "X" [--skip-stage ...]    │
│                                                                  │
│ pipeline-orchestrator (top-level)                                │
│  ├─ validates args (--skip-stage, --dry-run, --simulate-fail)   │
│  ├─ computes predicates (is_hybrid, has_api_spec)                │
│  └─ dispatches stage orchestrators sequentially                  │
│                                                                  │
│      Stage 1: Analytics (parallel)                               │
│      ├─ requirements-analyst                                     │
│      ├─ db-schema-reader                                         │
│      ├─ code-archaeologist (if is_hybrid)                        │
│      └─ api-spec-reader (if has_api_spec)                        │
│                                                                  │
│      Stage 2: Development (parallel, file partition)             │
│      ├─ kotlin-api-developer    (owns **/api/, **/controller/)    │
│      ├─ kotlin-data-architect   (owns **/domain/, db/migration/)│
│      ├─ kotlin-config-specialist (owns application*.yml)         │
│      └─ kotlin-integration-specialist (owns **/client/, ...)    │
│                                                                  │
│      Stage 3: Testing (parallel)                                 │
│      ├─ kotlin-unit-test-engineer                                │
│      ├─ kotlin-integration-test-engineer                         │
│      └─ kotlin-e2e-test-engineer                                 │
│      + kotlin-quality-gate-enforcer                              │
│                                                                  │
│      Bug Council (5 agents, when triggered)                      │
│      ├─ root-cause-analyst, code-archaeologist, pattern-matcher  │
│      └─ systems-thinker, adversarial-tester                       │
└──────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│ Hook Layer (event-driven shell)                                  │
│  PreToolUse  → pre-tool-use-hook.sh  (scope + danger check)      │
│  PostToolUse → post-tool-use-hook.sh (gate detection)            │
│  Stop        → stop-hook.sh          (block exit w/o EXIT_SIGNAL)│
│  PreCompact  → pre-compact.sh         (state save)                │
│  SessionStart→ session-start.sh     (init)                       │
│  SessionEnd  → session-end.sh         (cleanup)                   │
│  Notification→ persistence-hook.sh  (anti-abandonment)           │
└──────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────┐
│ State Layer                                                      │
│  .devteam/devteam.db (SQLite)                                    │
│  Tables: sessions, session_state (KV), events, tasks, gates      │
│  Stage tracking: session_state KV (no schema migration)         │
└──────────────────────────────────────────────────────────────────┘
```

---

## 3. Deployment context in Qwen Code

### Install lifecycle

```
[Developer]                                  [Qwen Code]
    │                                            │
    │ git clone + git submodule update           │
    │ bash scripts/sync-kotlin-skills.sh         │
    │                                            │
    │ bash install.sh [project-path] ──────────► copy agents/commands/skills/hooks to <target>
    │                                            │ deep-merge hooks into <target>/settings.json
    │                                            │ (absolute paths: <target>/hooks/run-hook.sh)
    │                                            │ create sentinel <target>/.devteam-installed
    │                                            │ (project-level: <project>/.qwen/;
    │                                            │  user-level: ~/.qwen/)
    │                                            │
    │ Restart Qwen Code                          │
    │                                            │ Auto-load QWEN.md
    │                                            │ Discover:
    │                                            │   - 16 commands/devteam/*.md
    │                                            │   - 35 skills/<name>/SKILL.md
    │                                            │   - 18 agents/<name>.md
    │                                            │
    │ /devteam:build --feature "X" ──────────────►  Slash command triggered
    │                                            │
    │                                            │ Read commands/devteam/build.md
    │                                            │ → orchestration logic
```

**Target resolution:**
- `bash install.sh /path/to/project` → `<project>/.qwen/`
- `bash install.sh` inside git → `<cwd>/.qwen/`
- `bash install.sh` outside git → `~/.qwen/`

### Files

- **`qwen-extension.json`** (24 lines) — manifest. `contextFileName: "QWEN.md"`.
- **`QWEN.md`** (84 lines, English) — auto-loaded context for the model.
- **`README.md`** (English) — user documentation.
- **`install.sh` / `uninstall.sh`** — self-contained shell scripts
  (shell + jq, no Python).

---

## 4. Architectural layers

### 4.1 Manifest `qwen-extension.json`

```json
{
  "name": "devteam",
  "version": "6.0.0",
  "description": "Kotlin + Spring backend 3-stage pipeline (Analytics → Development → Testing) with parallel sub-stages. Integrates skills from yalishevant/kotlin-backend-agent-skills.",
  "mcpServers": {
    "github": {...},
    "memory": {...},
    "semgrep": {...},
    "cocoindex": {...}
  },
  "contextFileName": "QWEN.md",
  "commands": "commands",
  "skills": "skills",
  "agents": "agents"
}
```

Fields:
- `commands` / `skills` / `agents` — directories Qwen Code scans
- `contextFileName` — file auto-loaded into system prompt
- `mcpServers` — GitHub, memory, semgrep, and graphfocus MCP servers (optional)

### 4.2 Slash commands (`commands/devteam/<name>.md`)

16 commands, one per `.md` file. Frontmatter (validated by Qwen Code):

```yaml
---
description: "Execute implementation work."
argument-hint: "--feature "..." [--skip-stage X]"
---
```

| Command | Purpose |
|---|---|
| `/devteam:build` | Full 3-stage pipeline (with `--skip-stage`, `--dry-run`, `--simulate-fail-stage`) |
| `/devteam:analyze` | Stage 1 only |
| `/devteam:develop` | Stage 2 only |
| `/devteam:test` | Stage 3 only |
| `/devteam:review` | Read-only code review |
| `/devteam:bug` | Diagnose and fix bugs (with optional Bug Council) |
| `/devteam:status` / `list` / `logs` / `reset` | Observability |
| `/devteam:worktree` | Manage git worktrees |
| `/devteam:config` / `help` | Configuration |
| `/devteam:issue` / `issue-new` | GitHub issue integration |

### 4.3 Skills (`skills/<name>/SKILL.md`)

35 skills total:
- 25 from upstream `yalishevant/kotlin-backend-agent-skills` (synced
  via `scripts/sync-kotlin-skills.sh`)
- 5 new orchestration skills (pipeline-orchestrator, analytics-stage,
  development-stage, testing-stage, kotlin-quality-gate)
- 5 cross-cutting kept (autonomous-controller, bug-council,
  refactoring-coordinator, requirements-validator, scope-validator)

Frontmatter (validated by Qwen Code):

```yaml
---
name: <skill-name>           # required, kebab-case
description: <text>           # required, when to use
priority: <int>               # optional, higher = earlier in /skills
---
```

### 4.4 Subagents (`agents/<name>.md`)

18 subagents in flat layout:

| Group | Agents |
|---|---|
| Orchestrators (4) | `pipeline-orchestrator`, `analytics-orchestrator`, `development-orchestrator`, `testing-orchestrator` |
| Stage 1 (4) | `requirements-analyst`, `db-schema-reader`, `code-archaeologist`, `api-spec-reader` |
| Stage 2 (4) | `kotlin-api-developer`, `kotlin-data-architect`, `kotlin-config-specialist`, `kotlin-integration-specialist` |
| Stage 3 (3) | `kotlin-unit-test-engineer`, `kotlin-integration-test-engineer`, `kotlin-e2e-test-engineer` |
| Cross-cutting (3) | `kotlin-quality-gate-enforcer`, `refactoring-coordinator`, `scope-validator`, `requirements-validator`, `autonomous-controller` (5) |

Wait — that's 4+4+4+3+5 = 20. But we said 18. The 2 extras are `bug-council-orchestrator` and the 5 bug-council members in the subdir.

Bug Council (5): `root-cause-analyst`, `code-archaeologist`,
`pattern-matcher`, `systems-thinker`, `adversarial-tester`,
coordinated by `bug-council-orchestrator`.

**Total flat .md files in `agents/`**: 18.

Frontmatter (validated):

```yaml
---
name: <agent-name>           # required
description: <text>           # required
tools:                        # required, YAML list (NOT CSV)
  - read_file
  - edit
  - write_file
  - glob
  - grep_search
  - bash
  - agent
---
```

No `model:` field (Qwen Code picks the model tier).

### 4.5 Hooks (`hooks/*.sh`)

9 hook scripts + `run-hook.sh` shim + `hooks-config.json` fragment.

| Hook | Event | Matcher | Purpose |
|---|---|---|---|
| `pre-tool-use-hook.sh` | PreToolUse | Edit\|Write, Bash | Scope check, dangerous-command block |
| `post-tool-use-hook.sh` | PostToolUse | Edit\|Write, Bash | Track changes, detect gates |
| `stop-hook.sh` | Stop | `*` | Block exit without `EXIT_SIGNAL: true` |
| `pre-compact.sh` | PreCompact | manual\|auto | Save state before compaction |
| `session-start.sh` | SessionStart | startup\|resume | Init/resume session |
| `session-end.sh` | SessionEnd | `*` | Finalize session |
| `persistence-hook.sh` | Notification | idle_prompt | Anti-abandonment |
| `scope-check.sh` | (helper) | — | Reused by pre-tool-use |
| `run-hook.sh` (shim) | (all) | — | Maps Qwen Code stdin JSON → legacy env vars |

### 4.5b Human-in-the-Loop (HITL) gate (NEW in v6.1)

After Stage 1 (Analytics) completes, the `pipeline-orchestrator` pauses
and calls `ask_user_question` to obtain human approval before
dispatching Stage 2 (Development). Always-on for `/devteam:build`.

**Four options presented to the user**:

| Option | Effect on state |
|---|---|
| Approve and continue to Stage 2 | `stage.development.status = "pending"`, `hitl_action = "approve"` |
| Request changes (re-run Stage 1) | `stage.analytics.status = "pending"` (re-run), `hitl_action = "request_changes"` |
| Edit analysis.md manually, then continue | `stage.development.status = "pending"`, `hitl_action = "edit"` |
| Abort pipeline | `pipeline.active = "false"`, `hitl_action = "abort"`, NO `EXIT_SIGNAL` |

**State extension** (no schema migration; uses existing `session_state` KV):

| Key | Type | Set by |
|---|---|---|
| `stage.development.status` | + `"awaiting_approval"` | pipeline-orchestrator |
| `stage.development.hitl_paused_at` | ISO 8601 | pipeline-orchestrator (at pause) |
| `stage.development.hitl_action` | `approve\|edit\|request_changes\|abort` | pipeline-orchestrator (after user choice) |
| `stage.development.hitl_resolved_at` | ISO 8601 | pipeline-orchestrator (after user choice) |
| `stage.development.analysis_path` | path | pipeline-orchestrator (at pause) |

**Auto-skip HITL when**:
- `--skip-stage development` is passed
- `--skip-stage analytics,development` is passed
- Stage 1 produced no analysis.md

**Resume after Qwen Code restart**:
- `hitl_action = approve | edit` → resume Stage 2
- `hitl_action = request_changes` → re-run Stage 1
- `hitl_action = abort` → manual intervention required

**Verification** (V11 in `scripts/dry-run.sh`):
- `--simulate-hitl-approve` prints "USER CHOSE Approve" + continues
- `--simulate-hitl-reject` prints re-run + re-prompt
- `--simulate-hitl-edit` prints edit + continues
- `--simulate-hitl-abort` prints "PIPELINE ABORTED" with `EXIT_SIGNAL: false`

See Section 5 (Pipeline) for the flow diagram with the HITL gate.

### 4.6 State (`scripts/state.sh` + `.devteam/state/` — v6.2 file-based)

- **Sessions** — `.devteam/state/sessions/<id>.md` (YAML frontmatter
  + Markdown body). One file per session.
- **session_state KV** — `.devteam/state/kv/<key>` (one file per key).
  Values are plain text or JSON. Atomic writes via mkdir-lock.
- **Events** — `.devteam/state/events/<date>-events.md` (append-only,
  one file per day, never edited).
- **Agent runs** — `.devteam/state/agent-runs/<run-id>.md` (per-invocation).
- **Tasks** — `.devteam/state/tasks/<TASK-ID>.md` (per-task).
- **Quality gates** — `.devteam/state/gates.md` (append-only).
- **Circuit breaker** — `.devteam/state/circuit-breaker.md` (YAML).

`schema.sql` (v6.1) was replaced by `state-structure.md` (v6.2) — pure
documentation. No schema migration needed; new state files are
created by `scripts/state-init.sh`.

Stage tracking (including HITL state added in v6.1) uses the existing
`session_state` KV pattern (now stored as flat files in
`.devteam/state/kv/`).

**Concurrency**: mkdir-based locking (POSIX-portable, no `flock`
dependency). Each `set_kv_state()` / `atomic_write()` creates a sidecar
`<file>.lock` directory; mkdir returns EEXIST if already locked.

### 4.7 Hook installer (`install.sh`)

Shell script (jq + perl for cross-platform path substitution, no Python).
Accepts optional `project-path` argument. Copies agents/commands/skills/hooks
to `<target>` (project-level `<project>/.qwen/` or user-level `~/.qwen/`),
deep-merges `hooks/hooks-config.json` (with absolute paths) into
`<target>/settings.json`, creates sentinel `<target>/.devteam-installed`.
Idempotent. `uninstall.sh` mirrors target resolution and removes all artifacts.

---

## 5. Pipeline: 3-stage with parallel sub-agents

### 5.1 Stage 1: Analytics (parallel)

All sub-agents dispatched in **one assistant turn**.

| Sub-agent | Always? | Output section |
|---|---|---|
| `requirements-analyst` | yes | Requirements (ACs, NFRs, user stories) |
| `db-schema-reader` | yes | Entity Map (JPA/Exposed/jOOQ, migrations) |
| `code-archaeologist` | hybrid only | Existing Patterns (conventions, constraints) |
| `api-spec-reader` | if OpenAPI/Swagger detected | API Contract |

**Predicates** (computed before dispatch):

```python
is_hybrid_predicate = Path('.git').exists() or any(Path('.').glob('src/main/kotlin/**/*.kt'))
has_api_spec = glob for openapi.{yml,yaml,json} or swagger.{yml,yaml,json}
```

**Output**: `.devteam/plans/<plan-id>/analysis.md`.

### 5.2 Stage 2: Development (parallel, file partition)

Each sub-agent owns a **disjoint** set of file patterns:

| Agent | Owns |
|---|---|
| `kotlin-api-developer` | `src/main/kotlin/**/api/`, `**/controller/`, `**/routes/`, `**/dto/` |
| `kotlin-data-architect` | `src/main/kotlin/**/domain/`, `**/entity/`, `**/repository/`, `src/main/resources/db/migration/` |
| `kotlin-config-specialist` | `src/main/resources/application*.yml`, `**/logback*.xml`, `gradle.properties` |
| `kotlin-integration-specialist` | `src/main/kotlin/**/client/`, `**/infrastructure/`, `**/event/`, `**/messaging/` |

**Fallback for non-conforming layout**: if `analysis.md`'s Package
Layout section uses non-standard folder names, the orchestrator
injects the actual paths into each agent's prompt. If no
recognizable layout, fall back to **sequential** Stage 2 with a
single `kotlin-fullstack-developer` agent.

**Skills passed in each agent's prompt** (from upstream `skills/`):

- API agent: `spring-mvc-webflux-api-builder`,
  `spring-context-di-reasoning`, `domain-decomposition-api-design-advisor`,
  `error-model-validation-architect`,
  `jackson-kotlin-serialization-specialist`
- Data agent: `jpa-spring-data-kotlin-mapper`,
  `schema-migration-planner`, `transaction-consistency-designer`
- Config agent: `gradle-kotlin-dsl-doctor`,
  `configuration-properties-profiles-kotlin-safe`
- Integration agent: `integration-resilience-engineer`,
  `observability-integrator`

**Output**: code changes + `stage2.merge.md` (overlap check +
build verification: `./gradlew compileKotlin ktlintCheck detekt`).

### 5.3 Stage 3: Testing (parallel)

| Agent | Test scope |
|---|---|
| `kotlin-unit-test-engineer` | `src/test/kotlin/**/*Test.kt` (unit) |
| `kotlin-integration-test-engineer` | `src/test/kotlin/**/*IT.kt` (Spring Boot + Testcontainers) |
| `kotlin-e2e-test-engineer` | `src/test/kotlin/**/*E2ETest.kt` (REST Assured + WireMock) |

After all 3 complete, `kotlin-quality-gate-enforcer` runs:

```bash
./gradlew test integrationTest e2eTest
./gradlew ktlintCheck detekt
./gradlew koverXmlReport   # coverage must be >= pipeline.coverage.threshold
```

---

## 6. Failure handling and retry policy

Per-agent retry: up to `pipeline.retry.per_agent` times (default 2).
On retry, include the previous failure context in the agent's
prompt.

After max retries, halt the stage and emit:

```text
STAGE 2 FAILED
Failed agents (retries exhausted):
  - kotlin-data-architect: 2/2 retries. Last error: compile error in User.kt:42
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

**Bug Council** triggers independently: when 3+ consecutive failures
on the top model tier, or when the orchestrator explicitly invokes
`bug-council-orchestrator`.

---

## 7. Stage tracking via session_state KV

`session_state` table (existing, no schema change) holds JSON values:

```sql
INSERT INTO session_state (session_id, key, value) VALUES
  ('session-xxx', 'stage.analytics.status', '"completed"'),
  ('session-xxx', 'stage.analytics.started_at', '"2026-06-13T14:30:00Z"'),
  ('session-xxx', 'stage.analytics.completed_at', '"2026-06-13T14:35:00Z"'),
  ('session-xxx', 'stage.analytics.output', '".devteam/plans/<id>/analysis.md"'),
  ('session-xxx', 'stage.development.status', '"in_progress"'),
  ('session-xxx', 'stage.development.retry_counts', '{"kotlin-data-architect": 2}'),
  ('session-xxx', 'stage.testing.status', '"pending"'),
  ('session-xxx', 'pipeline.active', '"true"');
```

Shell access via `scripts/state.sh`:

```bash
set_kv_state "stage.analytics.status" "completed"
get_kv_state "stage.analytics.status"  # → "completed"
```

---

## 8. Hook events

| Event | Used by | Purpose |
|---|---|---|
| `PreToolUse` (Edit\|Write, Bash) | `pre-tool-use-hook.sh` | Scope check, danger check |
| `PostToolUse` (Edit\|Write, Bash) | `post-tool-use-hook.sh` | Gate detection |
| `Stop` (`*`) | `stop-hook.sh` | Block exit w/o `EXIT_SIGNAL` |
| `PreCompact` (manual\|auto) | `pre-compact.sh` | State save |
| `SessionStart` (startup\|resume) | `session-start.sh` | Init |
| `SessionEnd` (`*`) | `session-end.sh` | Finalize |
| `Notification` (idle_prompt) | `persistence-hook.sh` | Anti-abandonment |

Removed vs v5.0 (no longer used): `SubagentStart`, `SubagentStop`,
`TaskCompleted`, `WorktreeCreate`, `WorktreeRemove`, `TeammateIdle`,
LLM-prompt hooks.

**Exit codes** (Qwen Code contract):
- `0` — success
- `2` — **blocking error**, stderr to model
- other — non-blocking, execution continues

---

## 9. Data model (SQLite)

`scripts/schema.sql` defines 4 versions (v1, v2, v3, v4). v6.0 does
**not** add new tables. Stage tracking uses existing
`session_state` JSON column.

### Key tables

```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    started_at TIMESTAMP,
    ended_at TIMESTAMP,
    command TEXT,
    command_type TEXT,        -- plan, implement, bug, issue, build, ...
    status TEXT DEFAULT 'running',  -- running, completed, failed, aborted
    current_phase TEXT,
    current_task_id TEXT,
    current_iteration INTEGER DEFAULT 0,
    max_iterations INTEGER DEFAULT 10,
    consecutive_failures INTEGER DEFAULT 0,
    circuit_breaker_state TEXT DEFAULT 'closed',
    execution_mode TEXT DEFAULT 'normal',
    total_tokens_input INTEGER DEFAULT 0,
    total_tokens_output INTEGER DEFAULT 0,
    total_cost_cents INTEGER DEFAULT 0,
    bug_council_activated BOOLEAN DEFAULT FALSE
);

CREATE TABLE session_state (
    session_id TEXT NOT NULL REFERENCES sessions(id),
    key TEXT NOT NULL,
    value JSON NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (session_id, key)
);

CREATE TABLE events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    event_type TEXT NOT NULL,   -- gate_passed, gate_failed, agent_invoked, ...
    agent TEXT,
    model TEXT,
    iteration INTEGER,
    duration_ms INTEGER,
    data JSON
);

CREATE TABLE tasks (
    id TEXT PRIMARY KEY,
    session_id TEXT,
    title TEXT,
    description TEXT,
    status TEXT DEFAULT 'pending',  -- pending, in_progress, completed, failed
    agent_type TEXT,
    complexity_score INTEGER,
    scope_allow_patterns JSON,
    scope_forbid_patterns JSON,
    acceptance_criteria JSON
);

CREATE TABLE gates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT,
    task_id TEXT,
    gate_name TEXT,             -- tests, ktlint, detekt, kover, ...
    status TEXT,                -- pass, fail
    duration_ms INTEGER
);
```

---

## 10. State machine

### Session

```
       ┌──────┐
       │ start│
       └───┬──┘
           ▼
      ┌─────────┐
      │ running │◄──── resume
      └────┬────┘
           │
    ┌──────┼──────┐
    ▼      ▼      ▼
┌────────┐ ┌────┐ ┌──────────┐
│complete│ │fail│ │interrupt │
└────────┘ └────┘ └──────────┘
```

### Stage

```
   ┌────────┐  start  ┌─────────────┐  gate_pass   ┌──────────┐
   │pending ├────────►│ in_progress ├─────────────►│completed │
   └────────┘         └──────┬──────┘              └──────────┘
                            │
                     ┌──────┼──────┐
                     ▼      ▼      ▼
                 ┌───────┐ ┌────┐ ┌────────┐
                 │ failed│ │halt│ │skipped │
                 └───────┘ └────┘ └────────┘
```

---

## 11. Migration from v5.0.0

| v5.0.0 (Claude Code plugin) | v6.0.0 (Qwen Code extension) |
|---|---|
| Generic multi-agent (Python, TS, frontend) | Kotlin + Spring backend focused |
| 18 agents | 18 agents (rewritten) |
| 13 skills | 35 skills (added 25 from upstream Kotlin repo) |
| 17 slash commands | 16 slash commands (build/analyze/develop/test/review replaced implement/plan/design/review) |
| Single Task Loop (sequential) | 3-stage pipeline (parallel sub-agents) |
| LLM-prompt hooks | (removed; replaced by skills) |
| Quality-gate-enforcer (generic) | kotlin-quality-gate-enforcer (Kotlin toolchain) |
| SubagentStart, TeammateIdle, WorktreeCreate (hooks) | (removed; Qwen Code handles natively) |

**Removed agents** (moved to `legacy/claude-code/old-agents/`):
`api-developer-{python,typescript}`, `frontend-developer`,
`test-writer`, `security-auditor`, `quality-gate-enforcer`,
`task-loop`, `sprint-orchestrator`, `sprint-loop`,
plus 101 language-specific and niche specialists.

**Removed skills**: `backend-{python,typescript}`,
`frontend-developer`, `test-writer`, `security-auditor`,
`refactoring-coordinator` (re-added), `task-loop-orchestrator`,
`sprint-orchestrator`, `quality-gate-enforcer`.

**New commands**: `build`, `analyze`, `develop`, `test`, `review`.

**New skills**: 4 orchestration + 1 quality-gate + 25 upstream.

**New agents**: 4 orchestrators + 3 Stage-1 + 4 Stage-2 + 3 Stage-3
+ 1 kotlin-quality-gate-enforcer = 15 new.

---

## 12. Extension points — how to add components

### Add a new subagent

1. Create `agents/<name>.md` with proper frontmatter.
2. Restart Qwen Code — the agent appears in `/agents manage`.

### Add a new skill

1. Create `skills/<name>/SKILL.md` with proper frontmatter.
2. Restart Qwen Code — the skill appears in `/skills`.

### Add a new slash command

1. Create `commands/<group>/<name>.md` with proper frontmatter.
2. Invoke as `/<group>:<name>`.

### Add a new upstream skill

1. Place in `vendors/kotlin-backend-agent-skills/.agents/skills/<name>/SKILL.md`
   (or run `bash scripts/sync-kotlin-skills.sh` after `git submodule update`).
2. Restart Qwen Code.

---

## 13. Design decisions and trade-offs

### D1: 3 sequential stages, parallel sub-stages

**Why**: matches real engineering workflow (plan → build → test);
enables parallelism where it matters; gates between stages catch
problems early.

**Trade-off**: 3 stages is a one-way path; can't easily redo
Analytics after Development starts. Mitigated by `--skip-stage`.

### D2: File partition in Stage 2 (instead of sub-tasks)

**Why**: Kotlin/Spring projects have a conventional layout
(controller, service, repository, config). Sub-agents owning file
patterns work in parallel without conflict.

**Trade-off**: requires conventional layout. Fallback: detect and
remap paths from `analysis.md`, or fall back to sequential.

### D3: Skills as model-invoked, not orchestrator-invoked

**Why**: lets the model decide when to use a skill (e.g., activate
`spring-kotlin-code-review` for review), reducing orchestrator
complexity.

**Trade-off**: model can over- or under-invoke. Mitigated by
high-quality `description:` in each skill.

### D4: 25 upstream skills from a single repo

**Why**: one source of truth, easy to sync via git submodule.

**Trade-off**: if upstream renames/reorganizes, sync breaks.
Mitigated by V1 verification (sync-kotlin-skills.sh validates
structure).

### D5: `session_state` KV for stage tracking (no schema change)

**Why**: full backward compatibility with v5.0 session data;
no migration step.

**Trade-off**: less queryable than a dedicated table. Mitigated by
documented KV convention.

---

## 14. Limitations and known issues

- **Subagent frontmatter must list `tools:` as a YAML list** (not
  inline). Inline form (`tools: [a, b]`) is now also accepted by V2.
- **Coverage gate** uses Kover; projects without Kover plugin need
  alternative coverage config.
- **Upstream structure** may change — `sync-kotlin-skills.sh` falls
  back to `skills/` if `.agents/skills/` not found.
- **`scope-validator` hook** requires `.git/` (reads `git diff`) — may
  need adjustment for non-git projects.
- **15 new agent files** were created; bodies are templates; tune
  for specific project conventions.

---

## 15. Glossary

| Term | Definition |
|---|---|
| **Stage** | A major pipeline phase (Analytics, Development, Testing) |
| **Sub-agent** | Specialist agent dispatched in parallel within a stage |
| **Orchestrator** | Agent that dispatches sub-agents (no implementation) |
| **Predicate** | Boolean function computed before stage dispatch (e.g., `is_hybrid_predicate`) |
| **File partition** | Disjoint set of file patterns owned by one Stage 2 sub-agent |
| **Quality gate** | Check (tests, ktlint, detekt, kover) between or after stages |
| **`--dry-run`** | Print dispatch sequence without invoking agents |
| **`--skip-stage`** | Skip named stage(s) in the pipeline |
| **`EXIT_SIGNAL`** | Marker in assistant message allowing Stop hook to exit |
| **Sentinel file** | `<target>/.devteam-installed` — file-based install state (project-level: `<project>/.qwen/`, user-level: `~/.qwen/`) |

---

## 16. File map

```
devteam/
├── qwen-extension.json         # Manifest (version 6.0.0)
├── QWEN.md                     # Auto-loaded context
├── README.md                   # User documentation
├── arch.md                     # This document
├── CHANGELOG.md                # 5.0.0 → 6.0.0
├── CONTRIBUTING.md             # Contributor guide
├── install.sh / uninstall.sh   # Hooks installer (shell+jq)
│
├── commands/devteam/           # 16 slash commands
├── skills/                     # 35 skills
├── agents/                     # 18 subagents (flat)
├── hooks/                      # 9 scripts + shim + config
├── scripts/
│   ├── sync-kotlin-skills.sh   # vendor → skills sync
│   ├── dry-run.sh              # Shell mirror of pipeline
│   ├── state.sh / events.sh / db-init.sh
│   └── ...
├── vendors/                    # git submodule (kotlin skills)
├── .devteam/                   # Runtime state (gitignored)
├── docs/                       # User/dev documentation
├── tests/                      # Test suite
└── legacy/claude-code/         # Archived v5.0 files
```

---

## 17. Sequence: a full pipeline run

```
User     QwenCode  Stage1SubAgents  Stage2SubAgents  Stage3SubAgents  Hooks  SQLite
  │         │             │                │                │            │       │
  │ build   │             │                │                │            │       │
  ├────────►│             │                │                │            │       │
  │         │ read        │                │                │            │       │
  │         │ build.md   │                │                │            │       │
  │         │ compute    │                │                │            │       │
  │         │ predicates │                │                │            │       │
  │         │             │                │                │            │       │
  │         │ Stage 1 (parallel)         │                │            │       │
  │         ├────────────►                │                │            │       │
  │         │ agent(req)  │                │                │            │       │
  │         │ agent(db)   │                │                │            │       │
  │         │ agent(arch) │ (if hybrid)   │                │            │       │
  │         │ agent(spec) │ (if api)      │                │            │       │
  │         │◄───── outputs analysis.md ──┘                │            │       │
  │         │             │                │                │            │       │
  │         │ Stage 2 (parallel)         │                │            │       │
  │         ├────────────────────────────►                │            │       │
  │         │             │   agent(api)  │                │            │       │
  │         │             │   agent(data) │                │            │       │
  │         │             │   agent(cfg)  │                │            │       │
  │         │             │   agent(int)  │                │            │       │
  │         │             │   (PreToolUse scope checks)       │            │       │
  │         │             │   ──────────────────────────────►│            │       │
  │         │             │   ──────────────────────────────│            │       │
  │         │◄─────────── outputs code + stage2.merge.md ──┘            │       │
  │         │             │                │                │            │       │
  │         │ Stage 3 (parallel)         │                │            │       │
  │         ├─────────────────────────────────────────────►            │       │
  │         │             │                │   agent(unit)  │            │       │
  │         │             │                │   agent(int)   │            │       │
  │         │             │                │   agent(e2e)   │            │       │
  │         │             │                │   + q-gate     │            │       │
  │         │◄───────────────────────────────────────────── test results │       │
  │         │             │                │                │   ────────►│       │
  │         │             │                │                │            │       │
  │         │ TASK_COMPLETE + EXIT_SIGNAL                  │            │       │
  │         ├─────── Stop event ─────────────────────────────────────────►│       │
  │         │             │                │                │   stop-hook│       │
  │         │             │                │                │   sees EXIT│       │
  │         │             │                │                │   → exit 0 │       │
  │         │◄────────────────────────────────────────────  allow exit │       │
  │         │             │                │                │            │       │
  │ ◄───────│             │                │                │            │       │
  │ final   │             │                │                │            │       │
  │ output  │             │                │                │            │       │
```

---

**End of document.** For changes, open a PR with description of
which sections/flows are affected.
