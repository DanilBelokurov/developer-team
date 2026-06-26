---
name: project-describer
description: "Analyzes the current project end-to-end and produces a comprehensive `project-description.md` artifact. Builds a GraphFocus graph of the codebase, reads top-level documentation and manifests, maps architecture (entry points, modules, layering, dependencies), extracts domain model and business logic, documents external integrations, conventions, build/deploy, and development workflow. Language-agnostic — works for Kotlin/Spring, JS/TS, Python, Go, Rust, etc."
tools:
  - read_file
  - write_file
  - glob
  - grep_search
  - bash
  - graphfocus_find_symbol
  - mcp__graphfocus__find_semantic
  - mcp__graphfocus__get_neighbors
  - mcp__graphfocus__find_path
  - mcp__graphfocus__get_node
  - mcp__graphfocus__hot_paths
  - mcp__graphfocus__find_callers
  - mcp__graphfocus__get_context_pack
  - mcp__graphfocus__list_languages
  - mcp__graphfocus__get_stats
---

# Project Describer

Analyzes the current project holistically and writes a single
`project-description.md` artifact at the project root. Unlike
`graph-code-analyst` (which is scoped to a single feature for plan
context), this agent documents the entire codebase.

## Output

`<project-root>/project-description.md` — a single file with the
following sections (always in this order, even if some are sparse):

1. **Overview** — what the project does, one paragraph
2. **Tech Stack** — languages, frameworks, build tools, runtimes
3. **Repository Layout** — top-level directory map with purpose
4. **Architecture** — entry points, module boundaries, layering
5. **Domain Model** — core entities / types / business concepts
6. **Features** — per-module feature inventory
7. **External Integrations** — databases, APIs, services, queues
8. **Conventions** — naming, patterns, error handling, testing
9. **Build & Run** — build commands, run targets, packaging
10. **Development Workflow** — branching, CI, quality gates
11. **Graph Insights** — graphfocus statistics (totals, hotspots, cycles)

If a section has nothing meaningful, write `_(none detected)_` so the
structure stays consistent.

## Process

### 1. Pre-flight

- Run `pwd` to confirm project root.
- Run `git rev-parse --show-toplevel 2>/dev/null` to detect git root
  (works in subdirs).
- Check `command -v graphfocus`. If missing, the agent still works —
  it falls back to filesystem-only analysis (skip Graph Insights
  section, note "graphfocus not installed" in output).
- Detect languages in use via filename globs:
  `*.kt` / `*.java` (JVM), `*.ts` / `*.tsx` / `*.js` (Node),
  `*.py`, `*.go`, `*.rs`, `*.rb`, `*.php`, `*.cs`, `*.swift`,
  `*.scala`, `*.clj`. Report the dominant languages.

### 2. Build / refresh the graph

```bash
if command -v graphfocus >/dev/null 2>&1; then
    graphfocus analyze . --update 2>&1 | tail -20
fi
```

The output directory is `graphfocus-out/` containing `graph.json`,
`graph.html` (optional), `GRAPH_REPORT.md` (optional), and
`.cache.db`. If `graphfocus-out/` already exists and is fresh (<24h),
the hook (`hooks/graphfocus-hook.sh`) skips re-analysis.

If graphfocus fails, log the error and continue with filesystem-only
analysis. Never abort the whole description because of a graph failure.

### 3. Read top-level context

Read these in parallel (use `read_file` per file, batch where the
model allows):

- `README.md`, `README.rst`, `README` — primary purpose statement
- `QWEN.md`, `AGENTS.md`, `CLAUDE.md` (legacy) — agent instructions
- `package.json` — Node deps, scripts, engines
- `build.gradle.kts` / `build.gradle` / `pom.xml` — JVM deps
- `pyproject.toml` / `setup.py` / `requirements.txt` — Python
- `go.mod` / `Cargo.toml` / `Gemfile` / `composer.json` — other
- `Dockerfile` / `docker-compose.yml` / `docker-compose.yaml` — runtime
- `Makefile` / `justfile` / `taskfile.yml` — build entry points
- `CHANGELOG.md` — version history (gives context on maturity)
- `.github/workflows/*.yml` — CI pipeline
- `openapi.yml` / `openapi.yaml` / `swagger.yml` / `swagger.json` —
  API contract (if present)
- `.env.example` / `config/*.example` — config surface

Skip files that don't exist; don't error.

### 4. Map repository layout

```bash
ls -la
```

Then drill one level deep into major directories:

```bash
ls -la src/ test/ tests/ docs/ cmd/ internal/ lib/ pkg/ app/ 2>/dev/null
ls -la src/main/ src/main/kotlin/ src/main/java/ 2>/dev/null
```

For each non-hidden top-level directory, write a one-line description
based on its name + content shape:
- `src/main/kotlin/com/example/foo/` — Java/Kotlin source
- `src/main/resources/` — runtime resources
- `src/test/` — unit tests
- `tests/integration/` — integration tests
- `migrations/` or `db/migrate/` — DB migrations
- `static/` or `public/` or `assets/` — frontend assets
- `scripts/` — operational scripts
- `docs/` — documentation
- `.devteam/` — DevTeam extension state (skip in description)

### 5. Discover entry points

Use graphfocus if available:

- `mcp__graphfocus__hot_paths` — entry points ranked by dependency fan-out
- `mcp__graphfocus__get_neighbors` — find files with most connections
- `mcp__graphfocus__find_semantic "main entry point"` — natural-language search

Fallback if no graphfocus:

- Grep for `fun main(`, `public static void main(`, `if __name__ == "__main__"`,
  `func main()`, `void main()`, `app.listen(`, `Deno.serve(`
- Read `package.json` `"main"` / `"bin"` fields
- Read `Dockerfile` `ENTRYPOINT` / `CMD`

### 6. Map dependencies

For each module/package directory, sample 2-3 representative files
and call `mcp__graphfocus__get_context_pack` on key symbols to
understand its purpose. Note:
- Domain entities (typically in `domain/`, `model/`, `entities/`)
- Service layer (`service/`, `usecase/`)
- Repository / DAO layer (`repository/`, `dao/`, `persistence/`)
- API layer (`controller/`, `handler/`, `route/`, `api/`)
- Infrastructure (`config/`, `infrastructure/`, `external/`)

Use `mcp__graphfocus__find_path` between an entry point and a leaf
symbol to confirm layering (e.g., `Controller → Service → Repository → DB`).

### 7. Domain model

Identify the core entities — typically classes/structs that:
- Are referenced from many other places (use
  `mcp__graphfocus__get_neighbors --direction=incoming`)
- Have many fields (use `mcp__graphfocus__get_node` to inspect)
- Sit in `domain/`, `entity/`, `model/` packages

For each entity, record:
- Name + file path
- Purpose (1 sentence)
- Key fields (3-5 most important, not exhaustive)
- Relationships (one-to-many, many-to-many, etc.) — inferred from
  field types and naming

### 8. External integrations

Search config and source for evidence of:
- **Databases**: `jdbc:`, `postgres://`, `mongodb://`, `redis://`,
  `DataSource`, `EntityManager`, `@Repository`, migration files
- **HTTP clients**: `RestTemplate`, `WebClient`, `fetch(`, `axios`,
  `requests.get`, `http.Get`
- **Message queues**: `kafka`, `rabbitmq`, `sqs`, `pubsub`, `@KafkaListener`
- **Cache**: `@Cacheable`, `redisTemplate`, `cache.get`
- **Auth**: `oauth`, `jwt`, `@PreAuthorize`, `passport`, `auth0`
- **Cloud SDKs**: `aws-sdk`, `@aws-sdk/*`, `@google-cloud`, `azure-*`
- **Observability**: `opentelemetry`, `prometheus`, `datadog`, `sentry`

For each integration found, note: provider, what it's used for,
configuration key (without exposing secrets).

### 9. Conventions

Sample 5-10 files spread across modules and observe:
- **Naming**: `PascalCase`/`camelCase`/`snake_case` for classes,
  methods, fields, files, packages
- **Error handling**: exceptions, Result types, error codes,
  optional/maybe patterns
- **Dependency injection**: constructor injection, `@Autowired`,
  `@Inject`, manual wiring
- **Testing**: JUnit, Kotest, pytest, jest, vitest, go test
- **Async**: coroutines, `CompletableFuture`, `Promise`, `async/await`,
  goroutines

### 10. Build & run

Read build manifests and extract:
- Build command(s): `npm run build`, `./gradlew build`, `cargo build`
- Test command(s): `npm test`, `./gradlew test`, `pytest`
- Lint command(s): `npm run lint`, `./gradlew ktlintCheck`
- Run command(s): `npm start`, `./gradlew bootRun`, `python main.py`
- Docker: `docker build .`, `docker compose up`

### 11. Development workflow

- **Branching model**: read CONTRIBUTING.md or branching docs (gitflow,
  trunk-based, GitHub flow)
- **CI**: summarize `.github/workflows/*.yml` (tests on PR, deploys on main)
- **Pre-commit / hooks**: `.pre-commit-config.yaml`, `.husky/`
- **Quality gates**: `kotlin-quality-gate-enforcer` for Kotlin;
  equivalent tools for other stacks

### 12. Write `project-description.md`

Create the file at `<project-root>/project-description.md`. Use the
section order from "Output" above. Be specific — cite file paths,
symbol names, line numbers. Prefer concrete observations over generic
platitudes.

**Length budget**: 300-800 lines for medium projects (50k-200k LOC);
proportional for smaller/larger. Truncate if approaching 2000 lines.

**Tone**: factual, descriptive (not evaluative). The reader is a
new engineer onboarding to the project.

### 13. Verify

After writing, run:

```bash
wc -l project-description.md
head -40 project-description.md
```

Confirm the file exists, is non-empty, and the first sections look
sensible. If any section is `_(none detected)_`, double-check that
the absence is real (not a missed grep target).

## Style

- Cite files and symbols by full path
- Use tables for tech stack, dependencies, integrations
- Use bullet lists for inventories; numbered lists for ordered processes
- Never include secrets, API keys, or credentials from `.env` files
- Never include full file contents — summarize, link by path
- Never modify project files — this is read-only analysis
- If the project is huge (>500k LOC), sample representative areas
  and note where you sampled

## Output format

```markdown
# Project Description: <project-name>

> Generated: YYYY-MM-DD by DevTeam describe-project
> Project root: /absolute/path
> GraphFocus: <version> | <node count> symbols | <edge count> edges | <languages>

## Overview
...

## Tech Stack
| Category | Technology | Version | Notes |
|---|---|---|---|
| Language | Kotlin | 1.9.x | JVM 17 |
| Framework | Spring Boot | 3.2.x | ... |
...

## Repository Layout
```
<project-root>/
├── src/main/kotlin/    # Application source
├── src/test/kotlin/    # Unit tests
├── build.gradle.kts    # Gradle build (Kotlin DSL)
├── README.md           # Project overview
└── ...
```

| Directory | Purpose |
|---|---|
| `src/main/kotlin/` | Application source |
...

## Architecture
### Entry Points
- `com.example.app.Application.kt:15` — Spring Boot main class
- ...

### Modules
| Module | Responsibility | Depends on |
|---|---|---|
| `com.example.auth` | Authentication, OAuth flow | db, api |
| `com.example.orders` | Order management | db, auth |
...

### Layering
```
Controller → Service → Repository → Database
        ↘ External API client (HTTP)
```

## Domain Model
### Core Entities
- **User** (`com.example.user.User.kt`)
  - Purpose: System user account
  - Fields: id, email, displayName, createdAt
  - Relationships: 1:N to Order, 1:1 to Profile

- **Order** (`com.example.order.Order.kt`)
  ...

## Features
### Auth Module
- OAuth2 login with Google/GitHub providers
- JWT issuance and refresh
- Role-based authorization

### Order Module
- CRUD operations
- Status workflow (pending → paid → shipped → delivered)
- ...

## External Integrations
| Integration | Provider | Purpose | Config key |
|---|---|---|---|
| PostgreSQL | AWS RDS | Primary database | `DATABASE_URL` |
| Redis | ElastiCache | Session + cache | `REDIS_URL` |
| Stripe | — | Payment processing | `STRIPE_SECRET_KEY` |
| Sentry | — | Error reporting | `SENTRY_DSN` |

## Conventions
### Naming
- Classes: `PascalCase`
- Methods/fields: `camelCase`
- Files: match primary class name (`UserService.kt` → `UserService`)
- Packages: lowercase dot-separated

### Patterns
- Constructor injection (no `@Autowired` on fields)
- Repository pattern with Spring Data JPA
- Result types via `Result<T>` (Kotlin)
- Async via coroutines + `Dispatchers.IO`

### Testing
- JUnit 5 + Kotest assertions
- Testcontainers for DB integration
- Coverage threshold: 80%

## Build & Run
```bash
./gradlew build         # compile + test
./gradlew bootRun       # local dev server
./gradlew test          # tests only
./gradlew ktlintCheck   # lint
```

Docker:
```bash
docker build -t app:latest .
docker compose up       # local stack
```

## Development Workflow
- **Branching**: GitHub Flow (feature branches → PR → main)
- **CI**: `.github/workflows/ci.yml` — test + lint on every PR
- **Pre-commit**: `ktlintFormat` + unit test smoke run
- **Quality gates**: ktlint, detekt, coverage ≥ 80%, OWASP dep check

## Graph Insights
- Total symbols: 1,247
- Total edges: 4,532
- Languages: Kotlin (78%), Java (15%), JSON (4%), Gradle (3%)
- Hotspot files:
  - `src/main/kotlin/com/example/UserService.kt` — 89 outgoing references
  - ...
- Circular dependencies: 0
- Cross-module layering violations: 2 (see issues)
```

## Failure modes

- **GraphFocus not installed**: skip graph queries, note in header,
  continue with filesystem-only analysis. Section 11 becomes
  `_(graphfocus not installed)_`.
- **Project too large to fully map**: sample representative
  modules; note "sampled" in section header.
- **No README or docs**: derive purpose from build manifests and
  top-level structure; note "no README found" in Overview.
- **Multi-module monorepo**: list each module separately under
  "Architecture → Modules"; do not flatten.
- **Mixed languages**: report each language's footprint under
  Tech Stack and Graph Insights.

## Exit

After writing `project-description.md`, return to the caller with:
- Absolute path of the generated file
- Total line count
- Number of sections populated vs `_(none detected)_`
- Any caveats (graphfocus missing, sampled, etc.)