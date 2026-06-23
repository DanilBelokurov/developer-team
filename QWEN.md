# DevTeam — Kotlin + Spring Backend Pipeline

You have access to the **devteam** extension for Qwen Code. It provides
a 3-stage development pipeline (Analytics, Development, Testing) with
parallel sub-agents for Kotlin + Spring backend work.

## Pipeline at a glance

```
/devteam:build --feature "Add OAuth login"
  │
  ▼
┌──────────────────────────────────────────────────────────────┐
│ STAGE 1: Analytics (parallel)                                  │
│   ├─ requirements-analyst                                      │
│   ├─ db-schema-reader                                          │
│   ├─ code-archaeologist (if hybrid)                            │
│   └─ api-spec-reader (if OpenAPI/Swagger found)                │
│   Output: .devteam/plans/<id>/analysis.md                      │
└──────────────────────────────────────────────────────────────┘
  │
  ▼
┌──────────────────────────────────────────────────────────────┐
│ STAGE 2: Development (parallel, file partition)                │
│   ├─ kotlin-api-developer    (owns **/api/, **/controller/)     │
│   ├─ kotlin-data-architect   (owns **/domain/, db/migration/) │
│   ├─ kotlin-config-specialist (owns application*.yml)         │
│   └─ kotlin-integration-specialist (owns **/client/, **/event/)│
│   Output: code changes + stage2.merge.md                       │
└──────────────────────────────────────────────────────────────┘
  │
  ▼
┌──────────────────────────────────────────────────────────────┐
│ STAGE 3: Testing (parallel)                                    │
│   ├─ kotlin-unit-test-engineer                                 │
│   ├─ kotlin-integration-test-engineer                          │
│   └─ kotlin-e2e-test-engineer                                  │
│   + kotlin-quality-gate-enforcer (ktlint, detekt, kover)      │
└──────────────────────────────────────────────────────────────┘
  │
  ▼
EXIT_SIGNAL: true
```

## Commands

| Command | Purpose |
|---|---|
| `/devteam:build` | Full 3-stage pipeline (Analytics → Development → Testing) |
| `/devteam:analyze` | Stage 1 only (planning) |
| `/devteam:develop` | Stage 2 only (after analysis) |
| `/devteam:test` | Stage 3 only (after development) |
| `/devteam:review` | Read-only code review (uses `spring-kotlin-code-review` skill) |
| `/devteam:bug` | Diagnose and fix bugs (uses 5-agent Bug Council) |
| `/devteam:status` / `list` / `logs` / `reset` | Observability |
| `/devteam:worktree` | Manage git worktrees |
| `/devteam:config` / `help` | Configuration and help |

### Useful flags for `build`

```bash
/devteam:build --feature "Add OAuth login"                    # full pipeline
/devteam:build --feature "X" --skip-stage testing            # only Analytics + Development
/devteam:build --feature "X" --skip-stage analytics,development  # only Testing
/devteam:build --feature "X" --dry-run                       # print dispatch sequence, no agents invoked
/devteam:build --feature "X" --simulate-fail-stage=development  # test failure report format
```

## Subagents available

Orchestrators: `pipeline-orchestrator`, `analytics-orchestrator`,
`development-orchestrator`, `testing-orchestrator`.

Specialists (parallel sub-agents):

- **Stage 1**: `requirements-analyst`, `db-schema-reader`,
  `code-archaeologist`, `api-spec-reader`
- **Stage 2**: `kotlin-api-developer`, `kotlin-data-architect`,
  `kotlin-config-specialist`, `kotlin-integration-specialist`
- **Stage 3**: `kotlin-unit-test-engineer`,
  `kotlin-integration-test-engineer`, `kotlin-e2e-test-engineer`

Cross-cutting: `kotlin-quality-gate-enforcer`, `scope-validator`,
`requirements-validator`, `autonomous-controller`,
`refactoring-coordinator`.

Bug Council (5 agents): `root-cause-analyst`, `code-archaeologist`,
`pattern-matcher`, `systems-thinker`, `adversarial-tester`,
coordinated by `bug-council-orchestrator`.

## Skills available (35 total)

From upstream `yalishevant/kotlin-backend-agent-skills` (25):
`spring-mvc-webflux-api-builder`, `spring-context-di-reasoning`,
`spring-kotlin-code-review`, `spring-security-configurator-auditor`,
`jpa-spring-data-kotlin-mapper`, `schema-migration-planner`,
`transaction-consistency-designer`, `gradle-kotlin-dsl-doctor`,
`dependency-conflict-resolver`,
`configuration-properties-profiles-kotlin-safe`,
`integration-resilience-engineer`, `jackson-kotlin-serialization-specialist`,
`observability-integrator`, `performance-concurrency-advisor`,
`upgrade-breaking-change-navigator`, `test-suite-builder`,
`stacktrace-log-triage`, `production-incident-responder`,
`kotlin-idiomatic-refactorer-spring-aware`,
`kotlin-spring-proxy-compatibility`,
`java-kotlin-migration-assistant`, `domain-decomposition-api-design-advisor`,
`error-model-validation-architect`, `project-context-ingestion`,
`ci-cd-containerization-advisor`.

Orchestration skills (5): `pipeline-orchestrator`, `analytics-stage`,
`development-stage`, `testing-stage`, `kotlin-quality-gate`.

Cross-cutting skills (5, kept): `autonomous-controller`, `bug-council`,
`refactoring-coordinator`, `requirements-validator`, `scope-validator`.

## When the pipeline is the right tool

Use `/devteam:build` when the task:

- Touches multiple files across layers (controller + service + repo + config)
- Requires understanding the existing code or schema
- Needs both implementation and testing

For trivial single-file changes (1-2 lines), skip the pipeline and
make the change directly.

## Slash Commands: Always Dispatch via agent()

When you see a slash command (e.g. `/devteam:build`, `/devteam:analyze`),
the command's markdown file is loaded into context. **Your job is to dispatch
the work to the appropriate subagent — never to do it yourself.**

**Rule:** If a slash command exists for this workflow, call the `agent()` tool
immediately. Do not implement the feature directly.

Examples:
- `/devteam:build` → `agent(subagent_type="pipeline-orchestrator", ...)`
- `/devteam:analyze` → `agent(subagent_type="analytics-orchestrator", ...)`
- `/devteam:develop` → `agent(subagent_type="development-orchestrator", ...)`
- `/devteam:test` → `agent(subagent_type="testing-orchestrator", ...)`

**Why:** Subagents are specialists with precise instructions. Self-implementation
bypasses the entire pipeline architecture (analytics, parallel agents, quality gates).

## Quality gates

Every pipeline run goes through:

- **ktlint** + **detekt** (style/lint)
- **Kover** (coverage, threshold configurable, default 80%)
- **./gradlew test** (unit + integration + e2e)

Gate failures trigger per-agent retry up to
`pipeline.retry.per_agent` times (default 2), then halt the stage
with a structured failure report.

## State and persistence (v6.2 — file-based)

- Pipeline state: `.devteam/state/` (Markdown files, gitignored)
- Sessions: `.devteam/state/sessions/<id>.md` (YAML frontmatter)
- KV state (plan-isolated): `.devteam/state/kv/<plan-id>/<key>` (one file per key, per pipeline run)
- KV state (global): `.devteam/state/kv/global/<key>` (pipeline-agnostic)
- Events: `.devteam/state/events/<date>-events.md` (append-only)
- Plans: `.devteam/plans/<plan-id>/` (unchanged)
- Stage tracking: plan-isolated KV (`set_kv_state <key> <value> $PLAN_ID`)

v6.1 used SQLite; v6.2 replaced with file-based state for zero
external dependencies. See `scripts/state-structure.md` for full layout.

The `Stop` hook blocks session exit until `TASK_COMPLETE: <id>` and
`EXIT_SIGNAL: true` are emitted.

## Installation (two-step)

DevTeam uses a hybrid installation model:

| Component | Installation |
|-----------|--------------|
| agents/, commands/, skills/, MCP servers, QWEN.md | `qwen extensions install .` |
| Lifecycle hooks, state, sentinel | `bash install.sh` |

See `README.md` for full installation instructions.

## Environment

- Extension root: `$QWEN_PROJECT_DIR`
- Override: `DEVTEAM_ROOT` env var
- Hooks command: `$QWEN_PROJECT_DIR/hooks/run-hook.sh <hook-name>`
- Hooks installed by: `bash install.sh` (not by `qwen extension`)

## Configuration

Override defaults in `.devteam/config.yaml`:

```yaml
pipeline:
  retry:
    per_agent: 2
    on_failure: halt_stage   # or skip_failed_agent, halt_pipeline
  coverage:
    threshold: 80

quality_gates:
  kotlin:
    lint: [ktlint, detekt]
    coverage_tool: kover
    test_command: ./gradlew test
```

## Reference

- 18 active subagents in `agents/`
- 16 slash commands in `commands/devteam/`
- 35 skills in `skills/`
- 25 upstream skills (synced via `scripts/sync-kotlin-skills.sh`)
- Detailed architecture: `arch.md`
- Migration notes: `docs/MIGRATION_FROM_CLAUDE.md` and
  `legacy/claude-code/MIGRATION_REFERENCE.md`

## Do NOT

- Edit `.devteam/devteam.db` directly (use `scripts/state.sh`)
- Override `model:` field in agent frontmatter (Qwen Code picks)
- Re-implement orchestration logic — delegate to the stage orchestrators
- Modify files outside an agent's partition in Stage 2 (orchestrator will revert)
- **Self-implement when a slash command exists** — always call `agent()` tool first
