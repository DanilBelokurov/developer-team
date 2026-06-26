---
description: "Analyze the current project end-to-end: build a GraphFocus graph, study the code, and write a comprehensive project-description.md artifact at the project root. Language-agnostic — works for any stack."
argument-hint: [--output <path>] [--no-graph] [--sample]
---

# /devteam:describe-project

**IMMEDIATELY invoke the `project-describer` agent.**
Do NOT analyze or write the description yourself. Do NOT read files
or run commands outside of dispatching the agent.

You MUST call the `agent()` tool with `subagent_type="project-describer"`:

```
agent(subagent_type="project-describer", prompt="/devteam:describe-project [--flags]")
```

Read-only project analysis. Builds a GraphFocus knowledge graph of the
codebase, surveys the top-level structure and manifests, extracts the
domain model and external integrations, observes conventions, and writes
a single `project-description.md` artifact at the project root.

The output is a structured onboarding document suitable for a new
engineer joining the project. It is **descriptive**, not evaluative —
it records what the project *is*, not whether it is *good*.

## Usage

```bash
# Default — describe the current project, write to ./project-description.md
/devteam:describe-project

# Custom output path
/devteam:describe-project --output docs/onboarding/project.md

# Skip GraphFocus (filesystem-only analysis, faster but less complete)
/devteam:describe-project --no-graph

# Sample representative areas only (for very large codebases)
/devteam:describe-project --sample
```

## Flags

| Flag | Effect |
|---|---|
| `--output <path>` | Write to a custom path instead of `./project-description.md`. Relative paths resolve from the project root. |
| `--no-graph` | Skip GraphFocus analysis entirely. Useful when graphfocus is not installed, or when you want a faster run on a small project. The Graph Insights section becomes `_(graphfocus not installed)_`. |
| `--sample` | Sample representative modules instead of fully traversing the codebase. Recommended for projects > 500k LOC. Adds "sampled" note to section headers. |

## What the agent does

1. **Pre-flight** — detect project root, git root, available languages.
2. **Build the graph** — runs `graphfocus analyze . --update` if
   graphfocus is installed (or skipped via `--no-graph`).
3. **Read top-level context** — README, build manifests, Docker,
   CI workflows, OpenAPI specs, .env.example.
4. **Map repository layout** — one-line descriptions per top-level
   directory.
5. **Discover entry points** — `fun main`, `package.json:bin`,
   Dockerfile `ENTRYPOINT`, etc.
6. **Map dependencies** — uses graphfocus to walk from entry points
   to leaf symbols; verifies layering.
7. **Extract domain model** — entities, relationships, business logic.
8. **Document integrations** — databases, HTTP clients, queues, cache,
   auth, observability.
9. **Observe conventions** — naming, patterns, error handling,
   testing strategy.
10. **Document build & run** — commands extracted from manifests.
11. **Document workflow** — branching, CI, pre-commit, quality gates.
12. **Write `project-description.md`** — single artifact, 300-800
    lines for medium projects.

## Output

```
<project-root>/project-description.md
```

Sections (in order):

1. Overview
2. Tech Stack
3. Repository Layout
4. Architecture (entry points, modules, layering)
5. Domain Model (core entities)
6. Features (per-module inventory)
7. External Integrations (DB, APIs, services)
8. Conventions (naming, patterns, testing)
9. Build & Run
10. Development Workflow
11. Graph Insights (when graphfocus available)

A section with no detectable content is rendered as `_(none detected)_`
to preserve structure.

## Example output excerpt

```markdown
# Project Description: shop-platform

> Generated: 2026-06-26 by DevTeam describe-project
> Project root: /Users/dev/shop-platform
> GraphFocus: 0.4.2 | 4,213 symbols | 18,902 edges | Kotlin, Gradle, JSON

## Overview
E-commerce backend for the Shop Platform product. Handles customer
accounts, product catalog, cart, checkout, and order fulfillment.
Integrates with Stripe for payments, SendGrid for email, and AWS S3
for product images.

## Tech Stack
| Category | Technology | Version | Notes |
|---|---|---|---|
| Language | Kotlin | 1.9.22 | JVM 17 |
| Framework | Spring Boot | 3.2.5 | Web + Data JPA + Security |
| Build | Gradle | 8.5 | Kotlin DSL |
| Database | PostgreSQL | 15 | via Flyway migrations |
| Cache | Redis | 7 | session + product cache |
...
```

## When to run

- **Onboarding** — share with a new engineer joining the team
- **Handoff** — passing the project to another team
- **Audit** — periodic snapshot of what the project actually does
  (useful when docs drift from code)
- **Pre-refactor baseline** — capture the current state before a
  major rewrite
- **AI context** — feed the description into a model to ground
  future changes

## Idempotency

Re-running overwrites `project-description.md`. The graph index
(`graphfocus-out/`) is refreshed in place if older than 24 hours, or
left alone if fresh.

## Tips

- First run on a large repo can take a few minutes (graphfocus
  indexing dominates). Subsequent runs are fast due to caching.
- Use `--no-graph` for quick scratch descriptions when graphfocus
  isn't installed or you don't need full symbol-level mapping.
- Use `--sample` on multi-million-LOC repos to keep the output
  focused; the agent will note which areas were sampled.
- Combine with `/devteam:plan --feature "..."` to plan new work
  with the description as ground truth.

## What this command does NOT do

- It does not modify any project files. The only file written is
  `project-description.md`.
- It does not run tests, builds, or lints.
- It does not make recommendations or evaluate quality. Use
  `/devteam:review` for that.
- It does not push, commit, or branch. Pure read-only analysis.

## Related commands

- `/devteam:analyze --feature "..."` — feature-scoped analysis
  (writes `analysis.md` with plan context)
- `/devteam:review` — quality-focused code review
- `/devteam:plan` — interview-driven planning for new work
- `/devteam:status` — runtime session/cost dashboard