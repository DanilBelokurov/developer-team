# Вклад в DevTeam

Спасибо за интерес к DevTeam для Qwen Code.

## Настройка окружения разработки

```bash
git clone ?
cd devteam

# Установка расширения (project-level или user-level)
# Для live-разработки: установить в сам репозиторий devteam
bash install.sh           # user-level
# или project-level:
bash install.sh /path/to/devteam
```

**Примечание**: Для live-разработки установите в директорию devteam:
```bash
bash install.sh "$(pwd)"
```

Зависимости: Python 3.7+, jq, git, опционально Node.js + npx для MCP-серверов.

## Структура проекта

```
devteam/
├── qwen-extension.json      # Манифест расширения
├── QWEN.md               # Автозагружаемый контекст для модели
├── commands/devteam/        # Slash-команды (16)
├── skills/                  # Файлы скилов (12)
├── agents/                  # Определения сабагентов (18)
├── hooks/                   # Hook-скрипты (9 .sh + run-hook.sh shim)
├── scripts/                 # State, events, DB, schema
├── config/                  # Файлы конфигурации пайплайна (*.yaml, *.md)
└── .devteam/               # Runtime state (gitignored)
├── tests/                   # Тестовый набор
├── examples/                # Примеры использования
├── docs/                    # Пользовательская и разработческая документация
└── legacy/claude-code/      # Оригинальные файлы Claude Code (архив)
```

## Добавление сабагента

1. Выберите имя в kebab-case (например, `database-optimizer`).
2. Создайте `agents/<name>.md` по шаблону frontmatter:

   ```yaml
   ---
   name: database-optimizer
   description: Optimizes PostgreSQL query plans, identifies missing indexes, and proposes schema migrations. Use when the user reports slow queries or asks to tune database performance.
   tools:
     - read_file
     - write_file
     - glob
     - grep_search
     - bash
     - agent
   ---

   # Database Optimizer

   ## Your Role
   ...
   ```

   **Обязательные поля frontmatter** (валидируются Qwen Code, см.
   `docs/features/skills.md` для эквивалентных правил скилов):
   - `name` — kebab-case, уникальное
   - `description` — что делает агент и когда его использовать
   - `tools` — список имён инструментов, доступных агенту

3. Тело: напишите роль, возможности, процесс и формат вывода агента
   в чистом Markdown. Qwen Code прочитает это как есть и использует как
   system prompt сабагента.

4. Тестируйте через `/agents manage` в Qwen Code или задайте вопрос,
   соответствующий описанию — модель должна делегировать задачу.

## Добавление slash-команды

1. Создайте `commands/devteam/<command-name>.md`:

   ```markdown
   ---
   description: One-line description shown in /help.
   argument-hint: [required] [--flag <value>]
   ---

   # /devteam:command-name

   ## Your Process
   ...
   ```

2. Валидируемые поля:
   - `description` — обязательное
   - `argument-hint` — опциональное; только для подсказок UI

3. Команда станет доступна как `/devteam:command-name`.

## Добавление скила

1. Создайте `skills/<skill-name>/SKILL.md`:

   ```yaml
   ---
   name: <skill-name>
   description: What the skill does and when to use it. Include keywords users would naturally mention.
   priority: 10   # optional; higher = appears earlier in /skills
   ---

   # Skill Name

   ## Instructions
   ...
   ```

2. Валидируемые поля (см. `docs/features/skills.md`):
   - `name` — kebab-case, уникальное, валидируется по шаблону
     `/^[\p{L}\p{N}_:.-]+$/u`
   - `description` — непустое
   - `priority` — опциональное конечное число

3. Скилы — **model-invoked**: Qwen Code активирует их автоматически,
   когда описание совпадает с запросом пользователя. Пользователи также
   могут выполнить `/skills <name>` для явного вызова.

## Добавление хука

1. Создайте `hooks/<event-name>.sh` (или `.ps1` для Windows).
2. Скрипт получает ввод от Qwen Code через stdin (JSON). Если нужен
   legacy-контракт env-переменных (`CLAUDE_TOOL_NAME` и т.д.),
   вызывайте через `hooks/run-hook.sh`, который маппит stdin JSON в
   эти env-переменные автоматически.
3. Коды завершения:
   - `0` — успех, продолжить
   - `2` — блокирующая ошибка; stderr показывается модели
   - другое — неблокирующая ошибка; выполнение продолжается
4. Добавьте фрагмент в `hooks/hooks-config.json`, описывающий когда
   хук срабатывает (event, matcher, type=command, command).
5. Тестируйте, вызывая событие и проверяя вывод хука.

## Стиль кода

- Shell-скрипты: `set -euo pipefail`, `local` для переменных функций,
  snake_case для функций, UPPER_SNAKE_CASE для констант.
- Markdown: чёткий императивный язык, code fences для команд, без
  ссылок на Claude Code (используйте `$QWEN_PROJECT_DIR`,
  `qwen extensions …`).

## Тесты

```bash
bash tests/run-tests.sh                                  # существующие shell-тесты
bash install.sh                                          # второй запуск — no-op (идемпотентность)
bash install.sh /tmp/dt-test                             # project-level тест
bash uninstall.sh /tmp/dt-test                           # чистое удаление теста
```

## Процесс Pull Request

1. Создайте feature-ветку: `git checkout -b feature/<name>`
2. Внесите изменения
3. Протестируйте цикл install/uninstall:
   - `bash install.sh /tmp/dt-test` (project-level)
   - `bash install.sh /tmp/dt-test` (idempotency — должен пропустить)
   - `bash uninstall.sh /tmp/dt-test` (чистое удаление)
   - `rm -rf /tmp/dt-test`
4. Коммитьте с описательными сообщениями
5. Откройте PR

## Справочник

- **Архитектура**: [`arch.md`](arch.md) — детальная системная
  архитектура (слои, жизненный цикл запроса, Task Loop, Bug Council,
  anti-abandonment, модель данных, state machines, дизайнерские
  компромиссы).
- Полный индекс агентов: `agents/` (18 сабагентов)
- Полный индекс команд: `commands/devteam/` (17 slash-команд)
- Детальная документация: `docs/`
