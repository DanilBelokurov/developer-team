# DevTeam для Qwen Code — Руководство пользователя

**Версия**: 6.3.0 (пайплайн для Kotlin + Spring backend)
**Аудитория**: пользователи (не разработчики) расширения DevTeam для Qwen Code
**Время чтения**: ~20 минут полностью; ~5 минут только Quick Start

---

## Содержание

1. [Что такое DevTeam?](#1-что-такое-devteam)
2. [Быстрый старт (5 минут)](#2-быстрый-старт-5-минут)
3. [Пайплайн из 3 этапов](#3-пайплайн-из-3-этапов)
4. [Human-in-the-Loop (HITL) gate](#4-human-in-the-loop-hitl-gate)
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

**Production safety в v6.1**: после этапа аналитики пайплайн
**останавливается и ждёт вашего одобрения**, прежде чем перейти к
написанию кода. Это Human-in-the-Loop (HITL) gate — никакой код не
пишется без явного Approve.

### Когда использовать

Используйте `/devteam:build`, когда:

- ✅ Вы начинаете новую фичу, затрагивающую несколько файлов
- ✅ Хотите автоматическую генерацию тестов (unit + integration + e2e)
- ✅ Хотите, чтобы AI сначала понял существующую схему и код, а
  потом реализовал
- ✅ У вас Kotlin + Spring проект с Gradle
- ✅ Вы хотите **контролировать** переход от плана к коду (HITL)

**Не используйте для**:

- ❌ Исправлений в одну строку или тривиальных изменений — правите
  напрямую
- ❌ Не-Kotlin/Spring проектов (Python, JS, frontend и т.д.)
- ❌ Когда нужно только прочитать/исследовать код без реализации —
  используйте сабагент `Explore` или `/skills` напрямую

### Что вы получаете

Одной командой вы получаете:

1. **Структурированный анализ** — требования, понимание схемы, API
   контракт, package layout
2. **Human-in-the-Loop gate** — вы ревьюите анализ и одобряете
3. **Production-код** — реализован параллельно в 4 файловых
   партициях (API, data, config, integration)
4. **Комплексные тесты** — unit + integration (Testcontainers) + e2e
   (WireMock)
5. **Quality gates** — ktlint, detekt, Kover coverage (default 80%)

---

## 2. Быстрый старт (5 минут)

### Требования

- **Qwen Code** (свежая версия)
- **Python 3** — для хуков (run-hook.sh парсит stdin JSON)
- **jq** — для merge хуков в settings.json
- **Git** — для scope-проверок и worktree-ов
- **Java 17+** и **Gradle** — в целевом Kotlin/Spring проекте
- Опционально: **Node.js** (для GitHub MCP интеграции)
- Опционально: **Semgrep** (`brew install semgrep`) — статический анализ безопасности
- Опционально: **GraphFocus** (`pip install 'graphfocus[all]'`) — knowledge graph из кода (заменяет grep_search в агентах)

### Установка

```bash
# 1. Клонируем репозиторий
git clone https://github.com/michael-harris/devteam.git
cd devteam

# 2. Инициализируем git submodule (25 upstream Kotlin скилов)
git submodule update --init --recursive

# 3. Синхронизируем upstream скилы
bash scripts/sync-kotlin-skills.sh
# Output: "Done. 25 skills"

# 4. Устанавливаем расширение (project-level или user-level)
# Project-level (рекомендуется): в <project>/.qwen/ — изолирует от других проектов
bash install.sh /path/to/your/project

# User-level: в ~/.qwen/ — глобально для всех проектов без аргумента
bash install.sh

# 5. Перезапускаем Qwen Code
```

**Project-level vs User-level:**
- `bash install.sh /path/to/project` → устанавливает в `<project>/.qwen/`
- `bash install.sh` (внутри git) → auto-detect: `<cwd>/.qwen/`
- `bash install.sh` (вне git) → user-level: `~/.qwen/`


### Проверка

```bash
# Должен показать 35 скилов
/skills

# Должен показать 25 сабагентов
/agents manage

# Должен отобразить состояние системы
/devteam:status
```

### Первый запуск пайплайна

```bash
/devteam:build --feature "Добавить /health endpoint, который возвращает 200 OK с timestamp"
```

Что произойдёт:

1. **Этап 1 (Analytics)**: 3-4 параллельных агента пишут `analysis.md`
2. **★ HITL GATE ★**: пайплайн останавливается, вы видите 4 опции:
   Approve / Request changes / Edit / Abort
3. После вашего Approve — **Этап 2 (Development)**: 4 параллельных
   Kotlin-агента реализуют код
4. **Этап 3 (Testing)**: 3 параллельных test-инженера + quality gates
5. **Completion**: `TASK_COMPLETE` + `EXIT_SIGNAL: true`

---

## 3. Пайплайн из 3 этапов

DevTeam запускает три последовательных этапа. После Этапа 1 — HITL
gate (см. главу 4). Внутри каждого этапа сабагенты работают
**параллельно**.

### Этап 1: Analytics (параллельный)

Цель: понять фичу, существующую кодовую базу и модель данных.

| Сабагент | Всегда? | Что делает |
|---|---|---|
| `requirements-analyst` | да | Acceptance criteria, NFR, user stories |
| `db-schema-reader` | да | Entity map (JPA, Exposed, jOOQ, Flyway) |
| `code-archaeologist` | только в hybrid | Существующие паттерны, конвенции |
| `api-spec-reader` | если найден OpenAPI/Swagger | API контракт |

**Hybrid-режим** = у проекта есть история `.git/` ИЛИ существующие
Kotlin-исходники.

**Выход**: `.devteam/plans/<plan-id>/analysis.md`

### HITL Gate (после Stage 1)

Pipeline-orchestrator вызывает `ask_user_question` с 4 опциями.
Подробности в главе 4.

### Этап 2: Development (параллельный, с файловой партицией)

Цель: реализовать фичу в 4 файловых партициях параллельно.

| Сабагент | Owns | Spring layout |
|---|---|---|
| `kotlin-api-developer` | `**/api/`, `**/controller/`, `**/routes/`, `**/dto/` | Controllers, DTO, services |
| `kotlin-data-architect` | `**/domain/`, `**/entity/`, `**/repository/`, `db/migration/` | Entities, repos, migrations |
| `kotlin-config-specialist` | `application*.yml`, `logback*.xml`, `gradle.properties` | Config, profiles |
| `kotlin-integration-specialist` | `**/client/`, `**/infrastructure/`, `**/event/`, `**/messaging/` | HTTP clients, queues, events |

**Выход**: изменения кода + `stage2.merge.md`.

### Этап 3: Testing (параллельный)

| Сабагент | Область | Инструменты |
|---|---|---|
| `kotlin-unit-test-engineer` | `**/*Test.kt` | JUnit 5 + Kotest + MockK |
| `kotlin-integration-test-engineer` | `**/*IT.kt` | Spring Boot + Testcontainers |
| `kotlin-e2e-test-engineer` | `**/*E2ETest.kt` | REST Assured + WireMock |

После завершения — `kotlin-quality-gate-enforcer`:
- `./gradlew test integrationTest e2eTest`
- `./gradlew ktlintCheck detekt`
- `./gradlew koverXmlReport` (coverage ≥ 80%)

---

## 4. Human-in-the-Loop (HITL) gate

После Этапа 1 (Analytics) пайплайн **обязательно** останавливается
для вашего одобрения перед Этапом 2 (Development). Это **always-on**
для `/devteam:build` — production safety.

### 4 опции

Когда HITL срабатывает, вы видите:

```
★ HITL GATE ★ (always-on for /devteam:build)
  analysis.md: .devteam/plans/<plan-id>/analysis.md
  ask_user_question:
    > Approve and continue to Stage 2
    > Request changes (re-run Stage 1)
    > Edit analysis.md manually, then continue
    > Abort pipeline
```

| Опция | Что делает |
|---|---|
| **Approve and continue to Stage 2** | analysis.md ОК → Этап 2 стартует |
| **Request changes (re-run Stage 1)** | Анализ неполный → пайплайн re-run Этапа 1 с уточнённым input |
| **Edit analysis.md manually, then continue** | Вы правите файл вручную → пайплайн продолжается |
| **Abort pipeline** | Стоп здесь, без дальнейших этапов |

### Когда HITL пропускается

HITL автоматически **пропускается** в случаях:

- `--skip-stage development` (нет Этапа 2 → нечего одобрять)
- `--skip-stage analytics,development` (нет ни Аналитики, ни Разработки)
- Этап 1 не произвёл analysis.md (failed или empty)
- Используете отдельные команды `/devteam:analyze`, `/devteam:develop`,
  `/devteam:test` напрямую (вместо `/devteam:build`)

### Resume после рестарта Qwen Code

Если Qwen Code перезапустился, пока HITL был активен, пайплайн
**детектит paused state** при следующем запуске:

- `hitl_action == "approve" | "edit"` → продолжает с Этапа 2
- `hitl_action == "request_changes"` → re-run Этапа 1
- `hitl_action == "abort"` → manual intervention required

Чтобы вручную сбросить paused state:

```bash
/devteam:reset --circuit
```

### Где хранится HITL state

В `.devteam/state/kv/session_state`, ключи HITL:

| Ключ | Значения |
|---|---|
| `stage.development.status` | `pending` → `awaiting_approval` → `pending` → `in_progress` → `completed` / `failed` |
| `stage.development.hitl_paused_at` | ISO 8601 timestamp |
| `stage.development.hitl_action` | `approve` / `edit` / `request_changes` / `abort` |
| `stage.development.hitl_resolved_at` | ISO 8601 timestamp |
| `stage.development.analysis_path` | `.devteam/plans/<plan-id>/analysis.md` |

### Советы по HITL

- **Первый раз** — прочитайте `analysis.md` целиком перед Approve.
  Это 2-3 минуты, но экономит часы.
- **Если что-то не так** — Request changes. Pipeline re-run с
  уточнённым контекстом.
- **Edit вручную** — для тонких правок (исправить формулировку AC,
  добавить edge case).
- **Abort** — если поняли, что фича вообще не нужна.

---

## 5. Справочник команд

### `/devteam:build` — полный пайплайн

```bash
/devteam:build --feature "Добавить OAuth login с refresh tokens"
/devteam:build --feature "Добавить /health endpoint" --skip-stage testing
/devteam:build --feature "Рефакторинг UserService" --dry-run
```

**Флаги**:
- `--feature "..."` (обязательный)
- `--skip-stage X,Y` — пропустить указанные этапы
- `--pipeline.retry.per_agent=N` — переопределить retry count (default 2)
- `--simulate-fail-stage=NAME` — тест failure-отчёта
- `--dry-run` — печатает dispatch-последовательность
- `--simulate-hitl-approve|reject|edit|abort` — тест HITL flow

HITL срабатывает автоматически после Этапа 1.

### `/devteam:analyze` — только Этап 1

```bash
/devteam:analyze --feature "Добавить OAuth login"
```

Без HITL (Stage 1 сам по себе не требует одобрения). Запускает
только 3-4 сабагента и пишет `analysis.md`.

### `/devteam:develop` — только Этап 2

```bash
/devteam:develop
```

Требует наличия `analysis.md`. Без HITL (HITL — особенность
`/devteam:build`).

### `/devteam:test` — только Этап 3

```bash
/devteam:test
```

Без HITL. Запускает test-инженеров + quality gate.

### `/devteam:review` — read-only code review

```bash
/devteam:review                              # uncommitted
/devteam:review --files "src/main/kotlin/**"
/devteam:review --since main
```

### `/devteam:bug` — диагностика и фикс

```bash
/devteam:bug "Login падает для гостевых пользователей"
/devteam:bug "Утечка памяти" --council
```

### Observability

| Команда | Назначение |
|---|---|
| `/devteam:status` | Dashboard |
| `/devteam:list` | Все планы |
| `/devteam:logs` | Execution logs |
| `/devteam:reset` | Reset stuck/paused sessions |

---

## 6. Примеры использования

### Пример 1: Новая фича (greenfield)

```bash
# Plan + Implement + Test (всё в одном, с HITL)
/devteam:build --feature "Добавить регистрацию с email-верификацией"
# → Stage 1 → HITL (вы ревьюите) → Approve → Stage 2 → Stage 3 → Done
```

### Пример 2: Существующий проект

```bash
cd /path/to/spring-project
qwen extensions link /path/to/devteam

/devteam:build --feature "Добавить Kafka consumer для order events"
# Pipeline детектит .git/, запускает code-archaeologist (hybrid)
# → Stage 1 → HITL → Approve → Stage 2 → Stage 3 → Done
```

### Пример 3: Исправление бага

```bash
# Простой баг
/devteam:bug "NullPointerException когда у пользователя нет email"

# Сложный — Bug Council (5 параллельных диагностов)
/devteam:bug "Утечка памяти под нагрузкой" --council
```

### Пример 4: Только планирование

```bash
/devteam:analyze --feature "Мигрировать с JPA на jOOQ"
cat .devteam/plans/<plan-id>/analysis.md
# (Позже, если одобрили)
/devteam:develop
```

### Пример 5: Iterative refinement через HITL

```bash
# Первый запуск
/devteam:build --feature "Добавить REST endpoint для /users"
# → Stage 1 → HITL → "Approve"
# → Stage 2 → Stage 3 → Done

# Ой, endpoint должен быть /api/v1/users, не /users
# Сейчас HITL не сработает, но можно:
/devteam:build --feature "Добавить REST endpoint для /api/v1/users" --skip-stage analytics
# (использует существующий analysis.md как reference, но заново проходит HITL)
```

---

## 7. Флаги и опции

### `--feature "..."` (обязательный)

- ✅ Хорошо: "Добавить OAuth login с refresh tokens, поддержка Google
  и GitHub провайдеров, с PKCE flow"
- ❌ Слишком расплывчато: "Добавить login"

### `--skip-stage X,Y`

Валидные значения: `analytics`, `development`, `testing`. Поддерживает
comma-separated и space-separated (в кавычках).

### `--dry-run`

Печатает запланированную dispatch-последовательность, **включая
HITL gate**.

```
DRY-RUN: /devteam:build --feature "Add /health"
...
Stage 1: Analytics (parallel)
...
★ HITL GATE ★ (always-on for /devteam:build)
  analysis.md: .devteam/plans/<plan-id>/analysis.md
  ask_user_question:
    > Approve and continue to Stage 2
    > Request changes (re-run Stage 1)
    > Edit analysis.md manually, then continue
    > Abort pipeline
  --simulate-hitl-approve: USER CHOSE Approve
  -> set session_state: stage.development.status = "pending"
  -> set session_state: stage.development.hitl_action = "approve"

Stage 2: Development (parallel, file partition)
...
```

### `--simulate-hitl-approve|reject|edit|abort`

Тестирование HITL flow в dry-run:
- `approve` — печатает "USER CHOSE Approve", продолжает Этап 2
- `reject` — печатает "USER CHOSE Request changes", re-run Этапа 1 +
  re-prompt HITL
- `edit` — печатает "USER CHOSE Edit", продолжает Этап 2
- `abort` — печатает "USER CHOSE Abort", halt с `EXIT_SIGNAL: false`

---

## 8. Конфигурация

Конфигурация в `.devteam/config.yaml`:

```yaml
pipeline:
  retry:
    per_agent: 2
    on_failure: halt_stage
  coverage:
    threshold: 80
  hitl:                       # NEW in v6.1
    enabled: true             # always-on
    after_stage: development  # HITL fires before Stage 2
    pause_on: [analytics]     # alternative: trigger by stage completion
    resume_actions:           # what the user can do
      - approve
      - request_changes
      - edit
      - abort
```

### Отключить HITL (не рекомендуется)

```yaml
pipeline:
  hitl:
    enabled: false   # отключает HITL (production-unsafe)
```

---

## 9. Состояние и персистентность (v6.2 — файлы, не SQLite)

DevTeam сохраняет всё состояние в `.devteam/state/` (Markdown-файлы)
в корне проекта. Директория в `.gitignore`. **Не требует sqlite3**
(никаких внешних бинарников).

### Структура

```
.devteam/state/
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
  (id, started_at, status, current_phase, current_iteration, ...)
- **session_state KV** — `.devteam/state/kv/<key>` (stage.analytics.status,
  stage.development.hitl_action, pipeline.retry_counts, ...)
- **Events** — `.devteam/state/events/<date>-events.md` (append-only
  daily log, по одному файлу на день)
- **Agent runs** — `.devteam/state/agent-runs/<run-id>.md` (per-invocation)
- **Tasks** — `.devteam/state/tasks/<TASK-ID>.md`
- **Quality gates** — `.devteam/state/gates.md` (append-only)
- **Circuit breaker** — `.devteam/state/circuit-breaker.md` (YAML)

### `.devteam/plans/<plan-id>/`

```
.devteam/plans/plan-add-oauth-login-20260616-a3f9/
├── analysis.md           # Выход Этапа 1
├── stage2.merge.md       # Этап 2: проверка пересечений
└── checkpoints/          # auto-saved
```

### Просмотр состояния

```bash
# Текущая сессия
/devteam:status

# Все планы
/devteam:list

# Execution logs (читать .devteam/state/events/*.md напрямую)
ls .devteam/state/events/ | tail
cat $(ls -t .devteam/state/events/*.md | head -1)

# Логи конкретной сессии (поиск в events/)
grep "session_id: <id>" .devteam/state/events/*.md

# Просмотр KV state напрямую
cat .devteam/state/kv/stage.analytics.status
cat .devteam/state/kv/stage.development.hitl_action

# Просмотр session frontmatter напрямую
head -20 .devteam/state/sessions/<id>.md
```

### Сброс HITL pause

```bash
# Через Qwen Code
/devteam:reset --circuit

# Или вручную (удалите .devteam/state/kv/stage.development.status
# и pipeline.active):
rm .devteam/state/kv/stage.development.status
echo 'pipeline.active' > .devteam/state/kv/pipeline.active
```

### Backup

Один файл / директория — легко:

```bash
# Полный backup
tar -czf devteam-state-$(date +%Y%m%d).tar.gz .devteam/state/

# Или просто скопировать
cp -r .devteam/state .devteam/state.backup-$(date +%Y%m%d)
```

### Git-ignore и git-trackability

`.devteam/state/` в `.gitignore` по умолчанию. Если вы **хотите**
track'ить state в git (для истории/отладки), просто удалите эту
строку из `.gitignore`. MD-файлы нормально diff'ятся и ревьюятся
в PR'ах.

### Преимущества v6.2 над v6.1 (SQLite)

- **Нет `sqlite3` бинарника** — работает на любой системе
- **Human-readable** — `cat` любой файл, edit в любом IDE
- **Git-trackable** — diff в PR'ах
- **Trivial backup** — `cp -r .devteam/state backup/`
- **Нулевые зависимости** — pure POSIX shell

Trade-offs: медленнее для частых reads (file I/O vs indexed), нет
SQL queries, нет transactional semantics. Для масштаба DevTeam
несколько сессий в день — незаметно.

### Migration из v6.1 (если апгрейдите)

Если у вас `.devteam/devteam.db` от v6.1:

```bash
# 1. Recommended: конвертация
bash scripts/state-migrate-v61-to-v62.sh

# 2. Alternative: начать с нуля (state в gitignore, потеря не критична)
rm .devteam/devteam.db
bash install.sh
```

---

## 10. Troubleshooting

### HITL не появляется

**Симптом**: pipeline проходит все этапы без паузы.

**Решение**:
1. Убедитесь, что используете `/devteam:build` (не отдельные
   `/devteam:develop` / `/devteam:test`)
2. Проверьте, что Stage 1 не был пропущен: `--skip-stage analytics`
   → HITL не сработает
3. Проверьте, что `pipeline.hitl.enabled: true` в config

### HITL пауза не снимается после Approve

**Симптом**: после Approve pipeline ничего не делает.

**Решение**:
1. Проверьте state: `devteam:status`
2. Если `stage.development.status = "awaiting_approval"` —
   нажмите Approve ещё раз
3. Если pipeline завис, перезапустите Qwen Code — orchestrator
   детектит paused state

### Skills/команды не появляются после установки

**Решение**:
1. Перезапустите Qwen Code
2. Определите target установки:
   - Project-level: `ls <project>/.qwen/.devteam-installed`
   - User-level: `ls ~/.qwen/.devteam-installed`
3. Перезапустите install: `bash install.sh` или `bash install.sh /path/to/project`

### Stage fail

(см. v5.0 troubleshooting) — failure policy и retry logic без
изменений.

### HITL в headless mode

Если Qwen Code работает в headless / неинтерактивном режиме
(без возможности задавать вопросы), HITL автоматически
**default'ит в Approve** с warning-логом. Чтобы отключить
полностью: `pipeline.hitl.enabled: false` в config.

---

## 11. FAQ

### Что если я не хочу HITL?

Используйте отдельные команды:
```bash
/devteam:analyze --feature "X"     # без HITL
/devteam:develop                  # без HITL
/devteam:test                     # без HITL
```

Или отключите в config: `pipeline.hitl.enabled: false`.

### Можно ли настроить опции HITL?

Да, через config (см. главу 8). Можно:
- Изменить `pause_on` (по умолчанию после Analytics)
- Изменить список `resume_actions`
- Полностью отключить

### Что если я случайно выбрал Abort?

Перезапустите пайплайн — он возобновится с Этапа 2 (если
`hitl_action == "approve"`), или с Этапа 1 (если
`hitl_action == "request_changes"`).

Чтобы полностью перезапустить с нуля:
```bash
/devteam:reset --circuit
/devteam:build --feature "X"
```

### HITL замедляет работу?

Да, добавляет один round-trip (вы → Approve → pipeline continues).
Для trivial фич это overhead. Для сложных — экономит часы
неправильной реализации.

### Что если analysis.md очень большой?

Pipeline показывает путь к файлу (`analysis.md: .devteam/plans/<id>/analysis.md`).
Вы читаете файл вручную в редакторе, потом возвращаетесь в Qwen Code
и выбираете действие.

### Можно ли иметь HITL после других этапов?

В v6.1 — только после Analytics. Расширение до HITL после
Development (перед Testing) — потенциально в v6.2.

### Где хранится HITL state?

В `.devteam/state/kv/session_state`:
- `stage.development.status = "awaiting_approval"`
- `stage.development.hitl_action`
- `stage.development.hitl_paused_at`
- `stage.development.hitl_resolved_at`

---

## 12. Глоссарий

| Термин | Определение |
|---|---|
| **HITL** | Human-in-the-Loop — пайплайн останавливается для человеческого одобрения |
| **Subagent** | Специализированный AI, вызываемый через `agent({ subagent_type: "..." })` |
| **Skill** | Markdown-инструкция, активируемая моделью по совпадению описания |
| **Slash command** | User-invoked точка входа (`/devteam:build`) |
| **Stage** | Мажорная фаза пайплайна (Analytics, Development, Testing) |
| **Parallel** | Внутри этапа сабагенты запускаются в одном assistant turn |
| **File partition** | Непересекающийся набор файлов, принадлежащий одному сабагенту |
| **Predicate** | Булева функция перед dispatch (e.g., `is_hybrid_predicate`) |
| **Quality gate** | Проверка (tests, ktlint, detekt, kover) на границе этапа |
| **`EXIT_SIGNAL: true`** | Маркер, разрешающий Stop hook выход |
| **Anti-abandonment** | Система, не дающая модели "сдаться" |
| **Bug Council** | 5-агентная параллельная диагностическая команда |
| **Hybrid-проект** | Есть история `.git/` ИЛИ существующие Kotlin-исходники |
| **Sentinel-файл** | `~/.qwen/.devteam-installed` — файловое состояние установки |
| **awaiting_approval** | Новое состояние `stage.development.status` для HITL pause |

---

## Нужна дополнительная помощь?

- **Архитектура**: см. `arch.md`
- **Миграция с v5.0.0 (Claude Code plugin)**: см.
  `docs/MIGRATION_FROM_ANTHROPIC.md`
- **Для контрибьюторов**: см. `CONTRIBUTING.md`
- **GitHub issues**: https://github.com/michael-harris/devteam/issues
- **Документация Qwen Code**: https://qwen-code.dev/docs

---

**Удачной Kotlin + Spring разработки!** 🚀
