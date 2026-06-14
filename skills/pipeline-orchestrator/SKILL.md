---
name: pipeline-orchestrator
description: "Top-level guidance for running the 3-stage Kotlin + Spring backend pipeline. Use when a task requires multiple stages (analysis, implementation, testing) with parallel sub-agents."
priority: 10
---

# Pipeline Orchestrator Skill

You are the top-level coordinator for the Kotlin + Spring backend
development pipeline. Three sequential stages, parallel sub-agents
within each.

## Three stages

1. **Analytics** — parallel: requirements, DB schema, code review
2. **Development** — parallel: API, data, config, integration
3. **Testing** — parallel: unit, integration, e2e

## When to use

Activate when the user requests a non-trivial feature, fix, or
refactor that:
- Touches multiple files across layers (controller + service + repo)
- Requires understanding the existing code or schema
- Needs both implementation and testing

For trivial single-file changes (1-2 lines), skip the pipeline and
make the change directly.

## Process

1. Read the user's feature description
2. If ambiguous (< 5 words or missing key terms), ask 1-3 clarifying
   questions via `ask_user_question`
3. Compute predicates:
   - `is_hybrid_predicate` = `[ -d .git ] || find . -name "*.kt"`
   - `has_api_spec` = glob for `openapi.{yml,yaml,json}` or
     `swagger.{yml,yaml,json}`
4. Dispatch stage orchestrators:
   - `agent(subagent_type="analytics-orchestrator", ...)` (if not skipped)
   - `agent(subagent_type="development-orchestrator", ...)` (if not skipped)
   - `agent(subagent_type="testing-orchestrator", ...)` (if not skipped)
5. After all stages, emit `TASK_COMPLETE` + `EXIT_SIGNAL: true`

## Parallel sub-agents

Each stage orchestrator issues **parallel** `agent()` calls in one
assistant turn. Do NOT chain sub-agents sequentially.

## Stage skipping

If `analysis.md` already exists, can skip Stage 1.
If code changes are already in the working tree, can skip Stage 2.
If only need to verify existing tests, can skip Stages 1+2.

## Output

After all stages complete:
- `analysis.md` (Stage 1)
- Code changes committed (Stage 2)
- Test results + coverage (Stage 3)
- `TASK_COMPLETE` + `EXIT_SIGNAL: true`

## Failure handling

- Per-agent retry up to `pipeline.retry.per_agent` (default 2)
- On max retries, halt the stage and emit structured report
- See `agents/development-orchestrator.md` for retry details
