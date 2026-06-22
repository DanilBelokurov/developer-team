# DevTeam для Qwen Code — Руководство пользователя

**Версия**: 6.3.0 (пайплайн для Kotlin + Spring backend)

---

## Содержание

1. [Что такое DevTeam?](#1-что-такое-devteam)
2. [Быстрый старт (5 минут)](#2-быстрый-старт-5-минут)
3. [MCP серверы](#3-mcp-серверы)
4. [Пайплайн из 3 этапов](#4-пайплайн-из-3-этапов)
5. [Справочник команд](#5-справочник-команд)
6. [Примеры использования](#6-примеры-использования)
7. [Флаги и опции](#7-флаги-и-опции)
8. [Конфигурация](#8-конфигурация)
9. [Состояние и персистентность](#9-состояние-и-персистентность)
10. [Troubleshooting](#10-troubleshooting)
11. [FAQ](#11-faq)
12. [Глоссарий](#12-глоссарий)

---

## 1. Что такое DevTeam?

DevTeam — это **расширение Qwen Code**, которое запускает
мульти-агентный пайплайн разработки для проектов на **Kotlin +
Spring backend**. Оно диспатчит 18 специализированных AI-сабагентов
параллельно для end-to-end реализации фич: анализ → код → тесты.

### Когда использовать

Используйте `/devteam:build`, когда:

- ✅ Вы начинаете новую фичу, затрагивающую несколько файлов
  (controller + service + repository + config)
- ✅ Хотите автоматическую генерацию тестов (unit + integration + e2e)
- ✅ Хотите, чтобы AI сначала понял существующую схему и код, а
  потом реализовал
- ✅ У вас Kotlin + Spring проект с Gradle

### Что вы получаете

Одной командой вы получаете:

1. **Структурированный анализ** — требования, понимание схемы, API
   контракт, package layout
2. **Production-код** — реализован параллельно в 4 файловых
   партициях (API, data, config, integration)
3. **Комплексные тесты** — unit + integration (Testcontainers) + e2e
   (WireMock)
4. **Quality gates** — ktlint, detekt, Kover coverage
   (конфигурируемый порог, по умолчанию 80%)

---

## 2. Быстрый старт (5 минут)

### Требования

- **Qwen Code** (свежая версия) — https://qwen-code.dev
- **Python 3.7+** — нужен для hook-установщика
- **Java 17+** и **Gradle** — в целевом Kotlin/Spring проекте
- **Git** — для scope-проверок и worktree-ов
- Опционально: **Node.js** (для MCP интеграции)
- Опционально: **GraphFocus** (`pip install 'graphfocus[all]'`) — knowledge graph из кода (AST-based, 11 тулз)
- Подробнее о MCP серверах и инструментах: [docs/MCP_TOOLS.md](docs/MCP_TOOLS.md)

### Установка

```bash
# 1. Клонируем репозиторий
git clone ?
cd devteam

# 2. Устанавливаем расширение (project-level или user-level)
# Project-level (рекомендуется): в <project>/.qwen/ — изолирует от других проектов
bash install.sh /path/to/your/project

# User-level: в ~/.qwen/ — глобально для всех проектов без аргумента
bash install.sh

# 5. Перезапускаем Qwen Code (настройки применяются при перезапуске)
```

### Два сценария установки

| | `bash install.sh` | `qwen extensions install` (манифест) |
|---|---|---|
| **Что делает** | Копирует файлы + интегрирует hooks + инициализирует state | Декларирует ассеты + автозапуск MCP servers |
| **Hooks** | ✅ Все 11 хуков активны | ❌ Не поддерживаются |
| **State** | ✅ Инициализируется | ❌ Не создаётся |
| **MCP servers** | ❌ Не настраиваются | ✅ graphfocus, mcp-pgs-tool, atlassian |
| **Idempotency** | ✅ Sentinel-файл | ❌ Нет |
| **Изоляция** | Project-level (рекомендуется) | Только user-level |

**Рекомендация:** используйте `bash install.sh` для полной функциональности.

**Project-level vs User-level:**
- `bash install.sh /path/to/project` → устанавливает в `<project>/.qwen/`
  (`.devteam/` создаётся рядом с `.qwen/` — в корне проекта)
- `bash install.sh` (внутри git-репозитория) → auto-detect: `<cwd>/.qwen/`
- `bash install.sh` (вне git) → user-level: `~/.qwen/`

Idempotency: повторный запуск с тем же target — no-op ("already installed").

---

## 3. MCP серверы

DevTeam интегрируется с внешними сервисами через [Model Context Protocol](https://modelcontextprotocol.io) (MCP).

### 3.1 GraphFocus (автоматически)

**Назначение**: Knowledge graph на основе AST для анализа кодовой базы.

**Установка**:
```bash
pip install 'graphfocus[all]'
```

**Возможности** (11 инструментов):
| Инструмент | Описание |
|------------|----------|
| `find_symbol` | Поиск символов по имени/типу |
| `get_node` | Информация об узле + связи |
| `get_neighbors` | Обход N уровней от узла |
| `find_path` | Shortest path между узлами |
| `find_callers` | Кто вызывает функцию |
| `find_semantic` | TF-IDF семантический поиск |
| `hot_paths` | Entry points с зависимостями |
| `get_context_pack` | Контекст вокруг символа |

**Hook**: `graphfocus-hook.sh` автоматически обновляет индекс при старте сессии.

**Агенты**: Все 18 агентов используют `find_symbol` для навигации по коду.

### 3.2 Atlassian (автоматически)

**Назначение**: Интеграция с Jira и Confluence для обогащения требований.

**Установка**: Автоматически при `qwen extensions install .`

**Возможности** (2 инструмента):
| Инструмент | Описание |
|------------|----------|
| `jira_get_issue` | Получить issue по ключу (e.g. `PROJ-123`) |
| `confluence_get_page` | Получить страницу по URL/ID |

**Агент**: `requirements-analyst` парсит описание фичи на Jira-ключи и автоматически подтягивает контекст.

**Требования**: Atlassian API токен и URL экземпляра (настраиваются вручную в `settings.json`).

### 3.3 mcp-pgs-tool (вручную)

**Назначение**: Подключение к PostgreSQL для live-схемы БД.

**Установка**: Вручную в `settings.json`:
```json
{
  "mcpServers": {
    "pgs": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "mcp-pgs-tool"]
    }
  }
}
```

**Возможности** (8 инструментов):
| Инструмент | Описание |
|------------|----------|
| `pg_list_schemas` | Список схем в БД |
| `pg_list_tables` | Список таблиц |
| `pg_list_columns` | Колонки с типами |
| `pg_column_stats` | nullable, default, references |
| `pg_columns_not_in_any_index` | Ненужные индексы |
| `pg_stat_statements_top` | Топ запросов |
| `pg_table_activity` | Активность таблиц |
| `pg_health` | Здоровье БД |

**Агент**: `db-schema-reader` использует для получения live-схемы (дополнение к статическим файлам).

**⚠️ Ограничения**:
- Требует работающий PostgreSQL (localhost или remote)
- Не подходит для автоматической установки — у каждого проекта свои параметры подключения
- Требует `psql` в PATH для автоматического определения параметров
- При отсутствии подключения агент fallback на статический анализ (JPA entities, Flyway migrations)

### Сравнение MCP серверов

| Сервер | Авто | Вручную | Агент | Требования |
|--------|------|---------|-------|------------|
| GraphFocus | ✅ | pip install | Все | Python |
| Atlassian | ✅ | — | requirements-analyst | API токен |
| mcp-pgs-tool | ❌ | settings.json | db-schema-reader | PostgreSQL |

Подробная документация: [docs/MCP_TOOLS.md](docs/MCP_TOOLS.md)

---

### Проверка

После перезапуска Qwen Code откройте новую сессию и выполните:

```bash
# Должен показать 35 скилов (25 Kotlin + 10 оркестрации/crosscutting)
/skills

# Должен показать 25 сабагентов
/agents manage

# Должен отобразить состояние системы
/devteam:status
```

### Первый запуск пайплайна

```bash
# Попробуйте сначала тривиальную фичу, чтобы увидеть пайплайн в действии
/devteam:build --feature "Добавить /health endpoint, который возвращает 200 OK с timestamp"
```

Наблюдайте за выполнением:

- Этап 1 (Analytics): 3-4 параллельных агента пишут `analysis.md`
- Этап 2 (Development): 4 параллельных Kotlin-агента реализуют код
- Этап 3 (Testing): 3 параллельных test-инженера + quality gates
- Пайплайн завершён → `TASK_COMPLETE` + `EXIT_SIGNAL: true`

---

## 3. Пайплайн из 3 этапов

DevTeam запускает три последовательных этапа. Внутри каждого
этапа сабагенты работают **параллельно** (истинный параллелизм —
все они диспатчатся в одном assistant turn).

### Этап 1: Analytics (параллельный)

Цель: понять фичу, существующую кодовую базу и модель данных до
написания любого кода.

| Сабагент | Всегда? | Что делает |
|---|---|---|
| `requirements-analyst` | да | Acceptance criteria, NFR, user stories |
| `db-schema-reader` | да | Entity map (JPA, Exposed, jOOQ, Flyway) |
| `code-archaeologist` | только в hybrid | Существующие паттерны, конвенции |
| `api-spec-reader` | если найден OpenAPI/Swagger | API контракт |

**Hybrid-режим** = у проекта есть история `.git/` ИЛИ существующие
Kotlin-исходники. **Детекция OpenAPI** = glob для
`openapi.{yml,yaml,json}` или `swagger.{yml,yaml,json}`.

**Выход**: `.devteam/plans/<plan-id>/analysis.md`

### Этап 2: Development (параллельный, с файловой партицией)

Цель: реализовать фичу в 4 файловых партициях параллельно, без
конфликтов.

| Сабагент | Owns (владеет) | Spring layout |
|---|---|---|
| `kotlin-api-developer` | `**/api/`, `**/controller/`, `**/routes/`, `**/dto/` | Controllers, DTO, services |
| `kotlin-data-architect` | `**/domain/`, `**/entity/`, `**/repository/`, `db/migration/` | Entities, repos, migrations |
| `kotlin-config-specialist` | `application*.yml`, `logback*.xml`, `gradle.properties` | Config, profiles, secrets |
| `kotlin-integration-specialist` | `**/client/`, `**/infrastructure/`, `**/event/`, `**/messaging/` | HTTP clients, queues, events |

**Fallback**: если у вашего проекта нестандартные имена папок
(например, `presentation/` вместо `api/`), оркестратор детектит
это из `analysis.md` и инжектит реальные пути. Если layout вообще
не распознаётся — fallback на **последовательный** Этап 2.

**Выход**: изменения кода + `stage2.merge.md` (проверка пересечений
+ верификация сборки).

### Этап 3: Testing (параллельный)

Цель: комплексное покрытие тестами в трёх областях.

| Сабагент | Область | Инструменты |
|---|---|---|
| `kotlin-unit-test-engineer` | `**/*Test.kt` | JUnit 5 + Kotest + MockK |
| `kotlin-integration-test-engineer` | `**/*IT.kt` | Spring Boot + Testcontainers |
| `kotlin-e2e-test-engineer` | `**/*E2ETest.kt` | REST Assured + WireMock |

После завершения всех 3 `kotlin-quality-gate-enforcer` запускает:
- `./gradlew test integrationTest e2eTest`
- `./gradlew ktlintCheck detekt`
- `./gradlew koverXmlReport` (покрытие ≥ 80% по умолчанию)

### Quality gates

На каждой границе этапов — гейты:

| Между | Гейт |
|---|---|
| 1 → 2 | Анализ завершён (все параллельные агенты записали свои секции) |
| 2 → 3 | Верификация сборки: `./gradlew compileKotlin ktlintCheck detekt` |
| 3 → Done | Все тесты прошли, покрытие ≥ порога |

Провал гейта запускает **per-agent retry** (до
`pipeline.retry.per_agent` раз, по умолчанию 2). После max retries
этап останавливается со структурированным failure-отчётом.

---

## 4. Справочник команд

### `/devteam:build` — полный пайплайн

Запускает полный 3-этапный пайплайн.

```bash
/devteam:build --feature "Добавить OAuth login с refresh tokens"
/devteam:build --feature "Добавить /health endpoint" --skip-stage testing
/devteam:build --feature "Рефакторинг UserService" --dry-run
```

**Флаги**:
- `--feature "..."` (обязательный) — описание фичи
- `--skip-stage X,Y` — пропустить указанные этапы (analytics, development, testing)
- `--pipeline.retry.per_agent=N` — переопределить retry count (default 2)
- `--simulate-fail-stage=NAME` — для тестирования failure-отчёта
- `--dry-run` — напечатать dispatch-последовательность без вызова агентов

### `/devteam:analyze` — только Этап 1

Запускает только Analytics. Полезно для планирования без
реализации.

```bash
/devteam:analyze --feature "Добавить OAuth login"
```

Выход: `analysis.md` с требованиями, entity map и (если hybrid)
существующими паттернами.

### `/devteam:develop` — только Этап 2

Запускает только Development. Требует наличия `analysis.md`
(от предыдущего `analyze` или `build`).

```bash
/devteam:develop
/devteam:develop --feature "Добавить OAuth login"   # использует последний plan
/devteam:develop --plan-id plan-add-oauth-login-20260616-a3f9
```

### `/devteam:test` — только Этап 3

Запускает только Testing. Требует наличия изменений кода.

```bash
/devteam:test
/devteam:test --feature "Добавить OAuth login"
```

### `/devteam:review` — read-only code review

Ревью текущих изменений без запуска полного пайплайна.

```bash
/devteam:review                              # uncommitted
/devteam:review --files "src/main/kotlin/**"  # конкретные пути
/devteam:review --since main                 # vs branch
```

### `/devteam:bug` — диагностика и фикс

Диагностирует и исправляет баги. Опционально активирует Bug Council
(5 параллельных диагностических агентов) для сложных случаев.

```bash
/devteam:bug "Login падает для гостевых пользователей"
/devteam:bug "Утечка памяти под нагрузкой" --council
/devteam:bug "Race condition в checkout" --severity critical
```

### Команды observability

| Команда | Назначение |
|---|---|
| `/devteam:status` | Dashboard: состояние сессии, прогресс, стоимость |
| `/devteam:list` | Список всех планов, спринтов, задач |
| `/devteam:logs` | Просмотр execution logs |
| `/devteam:reset` | Сброс зависших сессий, очистка circuit breaker |

### Прочие команды

| Команда | Назначение |
|---|---|
| `/devteam:worktree` | Управление git worktree (subcommands: status, list, cleanup, merge) |
| `/devteam:config` | Просмотр/изменение `.devteam/config.yaml` |
| `/devteam:help` | Помощь по командам |
| `/devteam:issue` | End-to-end фикс GitHub issue |
| `/devteam:issue-new` | Создать новый GitHub issue |

---

## 5. Примеры использования

### Пример 1: Новая фича (greenfield проект)

Вы начинаете новый Kotlin/Spring проект, в котором пока мало кода.

```bash
# Этап 1: Планирование
/devteam:analyze --feature "Добавить регистрацию пользователей с подтверждением email"

# Просмотр плана
cat .devteam/plans/<plan-id>/analysis.md

# Этап 2: Реализация
/devteam:develop

# Этап 3: Тестирование
/devteam:test
```

Или все 3 одной командой:

```bash
/devteam:build --feature "Добавить регистрацию пользователей с подтверждением email"
```

### Пример 2: Существующий проект, добавление фичи

У вас есть готовый Spring Boot проект. Пайплайн должен определить
структуру кода и адаптироваться.

```bash
# Убедитесь, что вы в корне проекта
cd /path/to/your/spring-project

# Опционально: подключите расширение через link
qwen extensions link /path/to/devteam

# Планирование + реализация
/devteam:build --feature "Добавить Kafka consumer для order events"

# Просмотр результата
git diff
```

Пайплайн сделает:
- Детект `.git/` → запуск `code-archaeologist` (hybrid-режим)
- Чтение существующих entities и repositories
- Реализация нового кода по конвенциям проекта
- Генерация тестов, соответствующих существующим паттернам

### Пример 3: Исправление бага

Вы нашли баг. Хотите, чтобы DevTeam диагностировал и починил его.

```bash
# Простой баг
/devteam:bug "NullPointerException когда у пользователя не задан email"

# Сложный баг — активируем Bug Council (5 агентов параллельно)
/devteam:bug "Утечка памяти под высокой нагрузкой" --council
```

Bug Council запускает 5 специалистов параллельно:
1. `root-cause-analyst` — анализ ошибок, генерация гипотез
2. `code-archaeologist` — git history, детекция регрессий
3. `pattern-matcher` — похожие баги, anti-patterns
4. `systems-thinker` — архитектурные проблемы
5. `adversarial-tester` — edge cases, векторы атак

После 5 отчётов оркестратор синтезирует унифицированный план
фикса и делегирует подходящему специалисту.

### Пример 4: Тестирование существующего кода

Вы уже реализовали код вручную и хотите, чтобы DevTeam написал
для него тесты.

```bash
# Пропускаем Этапы 1 и 2, запускаем только Этап 3
/devteam:build --feature "Добавить тесты для существующего кода" --skip-stage analytics,development
```

### Пример 5: Только планирование (без реализации)

Вы хотите понять, что повлечёт за собой фича, прежде чем
коммититься на реализацию.

```bash
/devteam:analyze --feature "Мигрировать с JPA на jOOQ"

# Просмотр плана
cat .devteam/plans/<plan-id>/analysis.md
# - Requirements: ...
# - Entity Map: ...
# - Existing Patterns: ...
# - Package Layout: ...
# - Estimated complexity: ...
```

Затем, позже, если захотите реализовать:

```bash
/devteam:develop
```

Пайплайн читает существующий `analysis.md` и пропускает
ре-анализ.

---

## 6. Флаги и опции

### `--feature "..."` (обязательный для build/analyze/develop)

Описание фичи. Будьте конкретны:

- ✅ Хорошо: "Добавить OAuth login с refresh tokens, поддержка
  Google и GitHub провайдеров, с PKCE flow"
- ❌ Слишком расплывчато: "Добавить login"

### `--skip-stage X,Y`

Пропустить один или несколько этапов. Валидные значения:
`analytics`, `development`, `testing`. Поддерживает как
comma-separated, так и space-separated (в кавычках).

```bash
# Только Этап 1 (Analytics)
/devteam:build --feature "X" --skip-stage development,testing

# Только Этап 2 (после ручного анализа)
/devteam:build --feature "X" --skip-stage analytics

# Только Этап 3 (после ручной реализации)
/devteam:build --feature "X" --skip-stage analytics,development
```

**Ошибки**:
- `--skip-stage banana` → `ERROR: --skip-stage 'banana' is not one of: analytics development testing`
- `--skip-stage analytics analytics` → `ERROR: --skip-stage 'analytics' specified twice`
- `--skip-stage` (без значения) → `ERROR: --skip-stage requires an argument`

### `--dry-run`

Напечатать запланированную dispatch-последовательность без вызова
агентов. Полезно для верификации и понимания структуры пайплайна.

```bash
/devteam:build --feature "Добавить /health endpoint" --dry-run
```

Пример вывода:

```
DRY-RUN: /devteam:build --feature "Add /health endpoint"
Stage 0: Initialize
  -> set session_state: stage.analytics.status = "pending"
  -> set session_state: stage.development.status = "pending"
  -> set session_state: stage.testing.status = "pending"
Stage 1: Analytics (parallel)
  Predicate is_hybrid_predicate: true -> code-archaeologist INCLUDED
  Predicate has_api_spec: false -> api-spec-reader SKIPPED
  -> agent(requirements-analyst, ...)
  -> agent(db-schema-reader, ...)
  -> agent(code-archaeologist, ...)
Stage 2: Development (parallel, file partition)
  -> agent(kotlin-api-developer) — owns: **/api/, **/controller/
  -> agent(kotlin-data-architect) — owns: **/domain/, db/migration/
  -> agent(kotlin-config-specialist) — owns: application*.yml
  -> agent(kotlin-integration-specialist) — owns: **/client/, **/event/
  Overlaps: none
Stage 3: Testing (parallel)
  -> agent(kotlin-unit-test-engineer, ...)
  -> agent(kotlin-integration-test-engineer, ...)
  -> agent(kotlin-e2e-test-engineer, ...)
Retry policy: per_agent=2, on_failure=halt_stage
EXIT_SIGNAL: true
```

### `--simulate-fail-stage=NAME`

Протестировать формат failure-отчёта. Полезно для разработки и CI.

```bash
/devteam:build --feature "X" --simulate-fail-stage=development
```

Пример вывода:

```
STAGE 2 FAILED
Failed agents (retries exhausted):
  - kotlin-data-architect: 2/2 retries. Last error: simulated failure
Succeeded agents (output preserved):
  - kotlin-api-developer: 12 files
  - kotlin-config-specialist: 1 file
  - kotlin-integration-specialist: 3 files
```

### `--pipeline.retry.per_agent=N`

Переопределить количество retry по умолчанию (2).

```bash
/devteam:build --feature "X" --pipeline.retry.per_agent=3
```

---

## 7. Конфигурация

DevTeam читает конфигурацию из `.devteam/config.yaml` в корне
вашего проекта.

### Просмотр текущей конфигурации

```bash
/devteam:config --show
```

### Ключевые настройки

```yaml
# Поведение пайплайна
pipeline:
  retry:
    per_agent: 2        # max retries на упавшего агента
    on_failure: halt_stage   # или skip_failed_agent, halt_pipeline
  coverage:
    threshold: 80       # процент

# Quality gates
quality_gates:
  kotlin:
    lint: [ktlint, detekt]
    coverage_tool: kover
    test_command: ./gradlew test integrationTest e2eTest
```

### Редактирование конфигурации

```bash
/devteam:config --set pipeline.coverage.threshold=90
```

Или редактируйте `.devteam/config.yaml` напрямую. Изменения
вступают в силу при следующем запуске пайплайна.

### Сброс к defaults

```bash
/devteam:config --reset
```

---

## 8. Состояние и персистентность (v6.2 — файлы)

DevTeam сохраняет всё состояние в `.devteam/state/` (Markdown-файлы)
в корне вашего проекта. Директория в `.gitignore`.

### Структура `.devteam/state/`

```
state/
├── current-session.md                # pointer на активную сессию
├── sessions/<id>.md                  # per-session MD с frontmatter
├── kv/<key>                          # one file per KV key
├── events/<date>-events.md           # append-only daily log
├── agent-runs/<run-id>.md            # per-agent-run MD
├── tasks/<TASK-ID>.md                # per-task MD
├── circuit-breaker.md                # circuit breaker state
└── gates.md                          # quality gate log
```

### Что хранится

- **Sessions** — `.devteam/state/sessions/<id>.md` с YAML frontmatter
- **KV state (plan-isolated)** — `.devteam/state/kv/<plan-id>/<key>` (stage.*, hitl_*, retry_*, etc.)
- **KV state (global)** — `.devteam/state/kv/global/<key>` (pipeline-agnostic settings)
- **events** — `.devteam/state/events/<date>-events.md` (лог гейтов, вызовов, HITL actions)
- **agent runs** — `.devteam/state/agent-runs/<run-id>.md` (per-invocation)
- **tasks** — `.devteam/state/tasks/<TASK-ID>.md`
- **gates** — `.devteam/state/gates.md` (quality gate log)

### Просмотр

```bash
# Снапшот текущего state
head -30 .devteam/state/sessions/$(cat .devteam/state/current-session.md | cut -d/ -f2)
cat .devteam/state/kv/<plan-id>/stage.analytics.status

# События за сегодня
cat $(ls -t .devteam/state/events/*.md | head -1)
```

### Что в `.devteam/plans/<plan-id>/`

Для каждого запуска пайплайна создаётся директория:

```
.devteam/plans/plan-add-oauth-login-20260616-a3f9/
├── analysis.md           # Выход Этапа 1
├── stage2.merge.md       # Этап 2: проверка пересечений + верификация сборки
└── checkpoints/          # checkpoint-файлы (автосохранение)
```

### Просмотр состояния

```bash
# Текущая сессия
/devteam:status

# Все планы
/devteam:list

# Execution logs
/devteam:logs

# Логи конкретной сессии
/devteam:logs --session session-20260614-143022-a3f9
```

### Сброс состояния

Если сессия зависла (например, Stop hook заблокировал выход без
`EXIT_SIGNAL: true`):

```bash
/devteam:reset                # текущая сессия
/devteam:reset --all          # все зависшие сессии
/devteam:reset --circuit      # только circuit breaker
```

## 9. Troubleshooting

### Skills/команды не появляются после установки

**Симптом**: `/skills` не показывает скилы devteam; `/devteam:status`
неизвестна.

**Решение**:
1. Перезапустите Qwen Code (настройки применяются при перезапуске)
2. Определите, куда вы устанавливали:
   - Project-level: `ls <project>/.qwen/.devteam-installed`
   - User-level: `ls ~/.qwen/.devteam-installed`
3. Проверьте install: `cat <target>/settings.json | grep -A 5 devteam`
4. Перезапустите install: `bash install.sh` (user-level) или
   `bash install.sh /path/to/project` (project-level)

### Stop hook блокирует штатный выход

**Симптом**: не можете завершить сессию Qwen Code; модель
продолжает работать.

**Решение**: убедитесь, что ваше последнее сообщение ассистента
содержит:

```text
TASK_COMPLETE: <id>
EXIT_SIGNAL: true
```

Если модель не выдаёт это, вы можете:

1. Вручную напечатать "EXIT_SIGNAL: true" и завершить turn
2. Или запустите `/devteam:reset` для очистки зависшего
   состояния сессии
3. Затем начните новую сессию

### Этап пайплайна упал

**Симптом**: этап остановлен с отчётом `STAGE N FAILED`.

**Решение**:
1. Прочитайте failure-отчёт: он идентифицирует упавших агентов и
   успешных
2. Выход успешных агентов сохранён в working tree
3. Перезапустите с `--simulate-fail-stage=<name>` чтобы увидеть
   формат отчёта
4. Исправьте проблему вручную или уточните `--feature` и
   перезапустите
5. После max retries (`pipeline.retry.per_agent`) этап
   останавливается

### Coverage gate не пройден

**Симптом**: Этап 3 остановлен с "coverage < 80%".

**Решение**:
1. Понизьте порог (например, `--pipeline.coverage.threshold=70` или
   `pipeline.coverage.threshold: 70` в config)
2. Или добавьте тестов вручную и перезапустите
3. Или пропустите Этап 3 совсем: `--skip-stage testing`

### Ошибки GitHub MCP

**Симптом**: `/devteam:issue` падает с "github MCP not available".

**Решение**:
1. Установите `GITHUB_TOKEN`: `export GITHUB_TOKEN=<token>`
2. Установите Node.js (для `npx`): `brew install node` (macOS) или
   `apt install nodejs` (Linux)
3. Проверьте: `which npx && echo $GITHUB_TOKEN`

### Ошибки валидации `--skip-stage`

**Симптом**: "is not one of: analytics development testing" и т.д.

**Решение**: валидные значения ровно `analytics`, `development`,
`testing`. Проверьте опечатки. Поддерживается comma-separated и
space-separated (в кавычках).

---

## 10. FAQ

### Могу ли я использовать DevTeam с не-Kotlin проектами?

Нет. DevTeam v6.0 ориентирован на Kotlin + Spring. Сабагенты и
скилы специфичны для этого стека. Для других языков используйте
нативные возможности модели или соберите своё расширение.

### Могу ли я добавлять собственные сабагенты?

Да. См. `CONTRIBUTING.md` для шаблона. Добавьте `agents/<name>.md` с
правильным frontmatter и перезапустите Qwen Code.

### Могу ли я добавлять собственные скилы?

Да. Создайте `skills/<name>/SKILL.md` с правильным frontmatter
(`name`, `description`, опц. `priority`). Скил становится
модель-инвокабельным автоматически.

### В чём разница между `--dry-run` и реальным запуском?

`--dry-run` печатает запланированную dispatch-последовательность
без вызова каких-либо агентов. Никакие файлы не создаются, никакой
код не меняется, никакие тесты не запускаются. Полезно для
верификации и понимания структуры пайплайна.

Реальный запуск вызывает каждого сабагента параллельно (один
assistant turn на этап) и производит реальные результаты.

### Как работает anti-abandonment?

Три механизма:
1. **Persistence hook** на `Notification: idle_prompt` —
   переподключает модель, если она застряла
2. **Stop hook** — блокирует выход сессии без `EXIT_SIGNAL: true`
3. **Текстовый контракт** в `QWEN.md` — явный запрет фраз вроде
   "I cannot", "I'm unable to", "you should try manually"

В комбинации: модель не может сдаться. Если застряла — ретраит
или эскалирует на Bug Council.

### Что если я не согласен с решениями оркестратора?

Пайплайн — это инструмент, а не мандат. Вы можете:
- Откатить код через `git restore <file>` и перезапустить с
  уточнённым `--feature`
- Пропустить этапы с плохим выходом: `--skip-stage development`
- Добавить ручные правки между этапами
- Отредактировать `analysis.md` перед запуском Этапа 2
  (dev-оркестратор читает его)

### Сколько стоит каждый запуск пайплайна?

Зависит от модельного tier. Qwen Code выбирает tier. Примерно:
- Этап 1: 3-4 агента × ~2-5k токенов каждый = ~10-20k токенов
- Этап 2: 4 агента × ~10-50k токенов (написание кода) = ~40-200k токенов
- Этап 3: 3 агента × ~10-30k токенов каждый (написание тестов) = ~30-90k токенов
- Quality gates: минимум (запуск существующих инструментов)

Итого: ~80-300k токенов на запуск. Cost tracking в `/devteam:status`.

### Где хранится состояние проекта?

В `.devteam/` в корне вашего проекта:
- `state/` (v6.2) — файловое state (sessions, kv, events, agent-runs, tasks, gates, circuit-breaker)
- `plans/<plan-id>/` — артефакты конкретного запуска
- `checkpoints/` — автоматически сохранённые checkpoints
- `logs/` — execution logs

Эта директория в `.gitignore`. (В v6.2 файл `devteam.db`
больше не создаётся; всё state в `.devteam/state/`.)

### Как удалить расширение?

```bash
# Project-level (тот же путь, что при установке)
bash uninstall.sh /path/to/project

# User-level
bash uninstall.sh

# Убрать runtime state проекта
rm -rf <project>/.devteam/
# или user-level:
rm -rf ~/.devteam/
```

**Важно:** `uninstall.sh` удаляет sentinel, agents/, commands/, skills/,
hooks/ из целевого `.qwen/`, и очищает hooks из `settings.json`.
Runtime state (`.devteam/`) удаляется отдельно.


---

## 11. Глоссарий

| Термин | Определение |
|---|---|
| **Subagent** (сабагент) | Специализированный AI, вызываемый через `agent({ subagent_type: "..." })`. Имеет свой контекст и инструменты. |
| **Skill** (скил) | Markdown-инструкция, которую модель активирует по совпадению описания. Лежит в `skills/<name>/SKILL.md`. |
| **Slash command** | User-invoked точка входа. `/devteam:build` читает `commands/devteam/build.md`. |
| **Stage** (этап) | Мажорная фаза пайплайна (Analytics, Development, Testing). Последовательная. |
| **Parallel** | Внутри этапа сабагенты запускаются в одном assistant turn. Истинный параллелизм. |
| **File partition** | Непересекающийся набор файловых паттернов, принадлежащий одному сабагенту Этапа 2. |
| **Predicate** | Булева функция, вычисляемая до dispatch этапа (например, `is_hybrid_predicate`). |
| **Quality gate** | Проверка (tests, ktlint, detekt, kover) на границе этапа. |
| **`--dry-run`** | Напечатать dispatch-последовательность без вызова агентов. |
| **`--skip-stage`** | Пропустить один или несколько этапов (analytics/development/testing). |
| **`EXIT_SIGNAL: true`** | Маркер в сообщении ассистента, разрешающий Stop hook выход. |
| **Anti-abandonment** | Система, не дающая модели "сдаться". Три механизма: persistence hook, stop hook, текстовый контракт. |
| **Bug Council** | 5-агентная параллельная диагностическая команда для сложных багов. |
| **Hybrid-проект** | Есть история `.git/` ИЛИ существующие Kotlin-исходники. Триггерит `code-archaeologist`. |
| **Sentinel-файл** | `<target>/.devteam-installed` — файловое состояние установки (project-level: `<project>/.qwen/`, user-level: `~/.qwen/`). |

---

## Нужна дополнительная помощь?

- **Архитектура**: см. `arch.md` (English, comprehensive)
- **Для контрибьюторов**: см. `CONTRIBUTING.md`
- **Документация Qwen Code**: https://qwen-code.dev/docs

---

**Удачной Kotlin + Spring разработки!** 🚀
