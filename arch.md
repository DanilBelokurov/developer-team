# Архитектура DevTeam

**Версия**: 6.3.0

---

## Содержание

1. [Обзор](#1-обзор)
2. [Структура проекта](#2-структура-проекта)
3. [Пайплайн: 3 этапа](#3-пайплайн-3-этапа)
4. [Сабагенты](#4-сабагенты)
5. [Хуки](#5-хуки)
6. [Состояние (file-based)](#6-состояние-file-based)
7. [Точки расширения](#7-точки-расширения)
8. [Диаграмма последовательности](#8-диаграмма-последовательности)

---

## 1. Обзор

DevTeam — это **расширение Qwen Code** для автономной Kotlin + Spring backend разработки. Реализует **3-этапный пайплайн** (Analytics → Development → Testing) с **параллельными сабагентами** внутри каждого этапа.

### Ключевые принципы

1. **Qwen Code — среда выполнения.** LLM-сессия играет роль оркестратора (читает slash-команды, диспатчит сабагентов через `agent()`, реагирует на хуки).

2. **Декларативные сабагенты.** Сабагенты — Markdown-файлы с system prompt. Qwen Code читает их и вызывает через `agent()`.

3. **Скилы — model-invoked.** Каждый `SKILL.md` в `skills/<name>/` — специализированный набор инструкций, который модель активирует при совпадении описания с контекстом.

4. **Параллелизм внутри этапов, гейты между этапами.** Сабагенты внутри этапа работают в **один assistant turn** (истинный параллелизм). Quality gates сидят между этапами.

5. **Идемпотентная установка.** Sentinel-файл `<target>/.devteam-installed`. Поддержка project-level (`<project>/.qwen/`) и user-level (`~/.qwen/`).

6. **Файловое состояние (v6.2+).** Состояние хранится в Markdown-файлах `.devteam/state/`, без SQLite.

---

## 2. Структура проекта

```
devteam/
├── qwen-extension.json      # Манифест расширения
├── QWEN.md                  # Автозагружаемый контекст для модели
├── README.md                # Документация (рус)
├── CONTRIBUTING.md          # Гайд для контрибьюторов (рус)
├── CHANGELOG.md             # История версий
│
├── commands/devteam/        # 16 slash-команд
├── skills/                  # 36 скилов (skills/kotlin/ + skills/analytics-stage/, etc.)
├── agents/                  # 26 сабагентов
├── hooks/                   # 11 hook-скриптов + lib/hook-common.sh
├── scripts/                 # state.sh, events.sh, checkpoint.sh, etc.
├── config/                  # config.yaml, config.md
│
├── .devteam/                # Runtime state (gitignored)
│   ├── state/               # sessions/, kv/, events/, agent-runs/, tasks/, gates/
│   └── sync/                # Epiq sync daemon state
│
├── docs/                    # Документация
├── tests/                  # Тестовый набор
└── legacy/claude-code/     # Архив v5.0
```

### Файловая система состояния (v6.2)

```
.devteam/state/
├── current-session.md       # pointer на активную сессию
├── sessions/<id>.md        # frontmatter: session metadata
├── kv/
│   ├── global/<key>        # pipeline-agnostic keys
│   └── <plan-id>/<key>     # plan-isolated keys (stage.*, hitl_*, retry_*)
├── events/<date>.md        # append-only daily log
├── agent-runs/<run-id>.md  # per-invocation log
├── tasks/<TASK-ID>.md      # per-task state
├── gates.md                # quality gate log (append-only)
└── circuit-breaker.md      # circuit breaker state
```

---

## 3. Пайплайн: 3 этапа

```
/devteam:build --feature "X" [--skip-stage ...]
        │
        ▼
┌─────────────────────────────────┐
│ Stage 1: Analytics (parallel)   │
│ ├─ requirements-analyst         │
│ ├─ db-schema-reader             │
│ ├─ code-archaeologist (hybrid)  │
│ └─ api-spec-reader (OpenAPI)     │
└────────────┬────────────────────┘
             ▼
        HITL Gate (v6.1+)
        ask_user_question → approve/edit/request_changes/abort
             │
             ▼
┌─────────────────────────────────┐
│ Stage 2: Development (parallel) │
│ ├─ kotlin-api-developer         │
│ ├─ kotlin-data-architect       │
│ ├─ kotlin-config-specialist    │
│ └─ kotlin-integration-specialist│
└────────────┬────────────────────┘
             ▼
┌─────────────────────────────────┐
│ Stage 3: Testing (parallel)     │
│ ├─ kotlin-unit-test-engineer    │
│ ├─ kotlin-integration-test-eng. │
│ ├─ kotlin-e2e-test-engineer     │
│ └─ kotlin-quality-gate-enforcer │
└─────────────────────────────────┘
```

### Этап 1: Analytics

| Сабагент | Всегда? | Выход |
|---|---|---|
| `requirements-analyst` | да | Requirements (ACs, NFRs) |
| `db-schema-reader` | да | Entity Map |
| `code-archaeologist` | если hybrid | Существующие паттерны |
| `api-spec-reader` | если OpenAPI | API Contract |

**Предикаты:**
```python
is_hybrid = Path('.git').exists() or glob('src/main/kotlin/**/*.kt')
has_api_spec = glob('openapi.{yml,yaml,json}') or glob('swagger.{yml,yaml,json}')
```

**Выход:** `.devteam/plans/<plan-id>/analysis.md`

### Этап 2: Development

| Сабагент | Владеет |
|---|---|
| `kotlin-api-developer` | `**/api/`, `**/controller/`, `**/routes/`, `**/dto/` |
| `kotlin-data-architect` | `**/domain/`, `**/entity/`, `**/repository/`, `db/migration/` |
| `kotlin-config-specialist` | `application*.yml`, `logback*.xml`, `gradle.properties` |
| `kotlin-integration-specialist` | `**/client/`, `**/infrastructure/`, `**/event/`, `**/messaging/` |

**Fallback:** если layout нестандартный — берём пути из `analysis.md`.

**Выход:** код + `stage2.merge.md` (overlap check + `./gradlew compileKotlin ktlintCheck detekt`)

### Этап 3: Testing

| Сабагент | Область |
|---|---|
| `kotlin-unit-test-engineer` | `**/*Test.kt` |
| `kotlin-integration-test-engineer` | `**/*IT.kt` (Testcontainers) |
| `kotlin-e2e-test-engineer` | `**/*E2ETest.kt` (WireMock) |

После завершения `kotlin-quality-gate-enforcer`:
```bash
./gradlew test integrationTest e2eTest
./gradlew ktlintCheck detekt
./gradlew koverXmlReport  # >= threshold (default 80%)
```

### HITL Gate (v6.1)

После Этапа 1 оркестратор вызывает `ask_user_question`:

| Опция | Эффект |
|---|---|
| Approve | продолжить в Stage 2 |
| Edit | пользователь правит analysis.md вручную, затем Stage 2 |
| Request changes | перезапустить Stage 1 |
| Abort | остановить пайплайн |

**Auto-skip:** `--skip-stage development`, `--skip-stage analytics,development`, или отсутствие `analysis.md`.

### Failure handling

Per-agent retry: `pipeline.retry.per_agent` раз (default: 2).
After max retries: halt stage + structured failure report.

---

## 4. Сабагенты

**26 сабагентов** в плоской структуре `agents/`:

| Группа | Сабагенты |
|---|---|
| Оркестраторы (5) | `pipeline-orchestrator`, `analytics-orchestrator`, `development-orchestrator`, `testing-orchestrator`, `autonomous-controller` |
| Bug Council (6) | `bug-council-orchestrator`, `root-cause-analyst`, `code-archaeologist`, `pattern-matcher`, `systems-thinker`, `adversarial-tester` |
| Stage 1 (4) | `requirements-analyst`, `db-schema-reader`, `code-archaeologist`*, `api-spec-reader` |
| Stage 2 (4) | `kotlin-api-developer`, `kotlin-data-architect`, `kotlin-config-specialist`, `kotlin-integration-specialist` |
| Stage 3 (4) | `kotlin-unit-test-engineer`, `kotlin-integration-test-engineer`, `kotlin-e2e-test-engineer`, `kotlin-quality-gate-enforcer` |
| Cross-cutting (3) | `scope-validator`, `requirements-validator`, `refactoring-coordinator` |

*`code-archaeologist` используется и в Stage 1, и в Bug Council.

**Frontmatter:**
```yaml
---
name: <name>           # kebab-case, уникальное
description: <text>   # что делает и когда использовать
tools:                # список инструментов
  - read_file
  - write_file
  - glob
  - grep_search
  - bash
  - agent
---
```

---

## 5. Хуки

**11 hook-скриптов** в `hooks/`:

| Хук | Событие | Назначение |
|---|---|---|
| `pre-tool-use-hook.sh` | PreToolUse | Scope check, dangerous commands |
| `post-tool-use-hook.sh` | PostToolUse | Gate detection, change tracking |
| `stop-hook.sh` | Stop | Блокировка выхода без `EXIT_SIGNAL` |
| `pre-compact.sh` | PreCompact | State save перед compaction |
| `session-start.sh` | SessionStart | Init/resume сессии |
| `session-end.sh` | SessionEnd | Финализация сессии |
| `persistence-hook.sh` | Notification (idle_prompt) | Anti-abandonment |
| `scope-check.sh` | (helper) | Реиспользуется pre-tool-use |
| `graphfocus-hook.sh` | SessionStart | Auto-indexing knowledge graph |
| `epiq-sync-hook.sh` | Notification | Epiq board sync |
| `run-hook.sh` | (shim) | Maps stdin JSON → legacy env vars |

**Exit codes:**
- `0` — успех
- `2` — блокирующая ошибка, stderr → модели
- другое — неблокирующая, выполнение продолжается

**hook-common.sh** (`hooks/lib/`): библиотека-мост к file-based state (`scripts/state.sh`, `scripts/events.sh`).

---

## 6. Состояние (file-based)

**v6.2+** — всё состояние в Markdown-файлах, без SQLite.

### KV API (`scripts/state.sh`)

```bash
# Глобальный ключ
set_kv_state "pipeline.active" "true"
get_kv_state "pipeline.active"  # → "true"

# Plan-изолированный ключ
set_kv_state "stage.analytics.status" "completed" "<plan-id>"
get_kv_state "stage.analytics.status" "<plan-id>"
```

### Параллельные пайплайны

Каждый запуск пайплайна получает свой KV-директорий `kv/<plan-id>/`, что исключает race conditions между параллельными выполнениями.

### Concurrency

mkdir-based locking (POSIX-portable, без `flock`).

---

## 7. Точки расширения

### Добавить сабагента

1. Создать `agents/<name>.md` с frontmatter
2. Перезапустить Qwen Code

### Добавить скил

1. Создать `skills/<name>/SKILL.md` с frontmatter
2. Перезапустить Qwen Code

### Добавить slash-команду

1. Создать `commands/devteam/<name>.md`
2. Доступна как `/devteam:<name>`

### Добавить хук

1. Создать `hooks/<event-name>.sh`
2. Добавить фрагмент в `hooks/hooks-config.json`
3. Тестировать, вызывая событие

---

## 8. Диаграмма последовательности

```
User     QwenCode   Stage1Agents   Stage2Agents   Stage3Agents   Hooks
  │         │            │              │              │            │
  │ build   │            │              │              │            │
  ├────────►│            │              │              │            │
  │         │ read       │              │              │            │
  │         │ build.md   │              │              │            │
  │         │ predicates │              │              │            │
  │         │            │              │              │            │
  │         │ Stage 1 (parallel)         │              │            │
  │         ├───────────►│              │              │            │
  │         │            │              │              │            │
  │         │◄── outputs analysis.md ────┤              │            │
  │         │            │              │              │            │
  │         │ ask_user_question (HITL)  │              │            │
  │         ├──────────────────────────►│              │            │
  │         │            │              │              │            │
  │         │ Stage 2 (parallel)         │              │            │
  │         ├──────────────────────────┼─────────────►│            │
  │         │            │  agent(api)  │              │            │
  │         │            │  agent(data) │              │            │
  │         │            │  agent(cfg)  │              │            │
  │         │            │  agent(int)  │              │            │
  │         │◄──────────────────────────┼──────────────│            │
  │         │            │              │              │            │
  │         │ Stage 3 (parallel)         │              │            │
  │         ├────────────────────────────────────────►│            │
  │         │            │              │  agent(unit) │            │
  │         │            │              │  agent(int)  │            │
  │         │            │              │  agent(e2e)  │            │
  │         │            │              │  + q-gate    │            │
  │         │◄─────────────────────────────────────────│            │
  │         │            │              │              │            │
  │         │ TASK_COMPLETE + EXIT_SIGNAL              │            │
  │         ├────────── Stop event ───────────────────────────────►│
  │         │            │              │              │     stop-hook
  │         │◄─────────────────────────────────────────│    EXIT → exit 0
  │         │            │              │              │            │
  │ ◄──────│            │              │              │            │
```

---
