# MCP Servers и Инструменты

**Версия документа**: 1.0.0
**Обновлено**: 2026-06-22

---

## Обзор

DevTeam использует Model Context Protocol (MCP) для интеграции внешних серверов и инструментов. Все MCP инструменты доступны агентам через формат `mcp__<server>__<tool>`.

---

## MCP Серверы

### 1. GraphFocus (Knowledge Graph)

**Описание**: AST-based knowledge graph для анализа кода. Поддерживает 20 языков.

**Установка**:
```bash
pip install 'graphfocus[all]'
```

**Конфигурация в `qwen-extension.json`**:
```json
"graphfocus": {
  "type": "stdio",
  "command": "graphfocus",
  "args": ["mcp"]
}
```

**Hook**: `graphfocus-hook.sh` — auto-indexing knowledge graph при старте сессии.

### 2. Atlassian (Jira + Confluence)

**Описание**: MCP сервер для интеграции с Atlassian (Jira issues, Confluence pages).

**Агент**: Используется агентом `requirements-analyst` для обогащения требований из Jira/Confluence.

**Ручная установка** (в `settings.json`):
```json
{
  "mcpServers": {
    "atlassian": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-atlassian"]
    }
  }
}
```

**Требования**: Atlassian API токен и URL.

### 3. mcp-pgs-tool (PostgreSQL)

**Описание**: MCP сервер для подключения к PostgreSQL базе данных с introspection и health tools.

**Агент**: Используется агентом `db-schema-reader` для получения live-схемы БД.

**Ручная установка** (в `settings.json`):
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

**Требования**: PostgreSQL база данных, доступная по стандартным параметрам подключения.

---

## Доступные Инструменты

### GraphFocus Tools (11)

| Инструмент | Формат вызова | Описание |
|------------|---------------|----------|
| `find_symbol` | `mcp__graphfocus__find_symbol` | Поиск символов по имени/типу с фильтрацией по языку |
| `get_node` | `mcp__graphfocus__get_node` | Полная информация об узле + входящие/исходящие связи |
| `get_neighbors` | `mcp__graphfocus__get_neighbors` | Обход N уровней от узла |
| `find_path` | `mcp__graphfocus__find_path` | Shortest path между двумя узлами |
| `find_callers` | `mcp__graphfocus__find_callers` | Кто вызывает эту функцию/метод |
| `find_semantic` | `mcp__graphfocus__find_semantic` | TF-IDF семантический поиск |
| `hot_paths` | `mcp__graphfocus__hot_paths` | Entry points с большинством зависимостей |
| `get_context_pack` | `mcp__graphfocus__get_context_pack` | Контекст вокруг символа (исходный код) |
| `list_languages` | `mcp__graphfocus__list_languages` | Список языков в графе |
| `get_stats` | `mcp__graphfocus__get_stats` | Статистика графа |

### Atlassian Tools (2)

| Инструмент | Формат вызова | Описание |
|------------|---------------|----------|
| `jira_get_issue` | `mcp__atlassian__jira_get_issue` | Получить issue из Jira |
| `confluence_get_page` | `mcp__atlassian__confluence_get_page` | Получить страницу из Confluence |

### mcp-pgs-tool Tools (8)

| Инструмент | Формат вызова | Описание |
|------------|---------------|----------|
| `pg_list_schemas` | `mcp__mcp-pgs-tool__pg_list_schemas` | Список схем в БД |
| `pg_list_tables` | `mcp__mcp-pgs-tool__pg_list_tables` | Список таблиц |
| `pg_list_columns` | `mcp__mcp-pgs-tool__pg_list_columns` | Колонки с типами |
| `pg_column_stats` | `mcp__mcp-pgs-tool__pg_column_stats` | nullable, default, references |
| `pg_columns_not_in_any_index` | `mcp__mcp-pgs-tool__pg_columns_not_in_any_index` | Ненужные индексы |
| `pg_stat_statements_top` | `mcp__mcp-pgs-tool__pg_stat_statements_top` | Топ запросов |
| `pg_table_activity` | `mcp__mcp-pgs-tool__pg_table_activity` | Активность таблиц |
| `pg_health` | `mcp__mcp-pgs-tool__pg_health` | Здоровье БД |

---

## Использование в Агентах

### Декларация в Frontmatter

Агенты объявляют доступные инструменты в YAML frontmatter:

```yaml
---
name: kotlin-api-developer
description: "..."
tools:
  - read_file
  - edit
  - write_file
  - glob
  - mcp__graphfocus__find_symbol
---
```

### Активные Агенты с GraphFocus

Следующие агенты используют `mcp__graphfocus__find_symbol`:

| Агент | Stage |
|-------|-------|
| `analytics-orchestrator` | Orchestration |
| `development-orchestrator` | Orchestration |
| `testing-orchestrator` | Orchestration |
| `kotlin-api-developer` | Development |
| `kotlin-data-architect` | Development |
| `kotlin-config-specialist` | Development |
| `kotlin-integration-specialist` | Development |
| `kotlin-e2e-test-engineer` | Testing |
| `kotlin-quality-gate-enforcer` | Testing |
| `api-spec-reader` | Analytics |
| `requirements-analyst` | Analytics |
| `scope-validator` | Cross-cutting |
| `requirements-validator` | Cross-cutting |
| `autonomous-controller` | Cross-cutting |
| `pattern-matcher` | Bug Council |
| `systems-thinker` | Bug Council |
| `adversarial-tester` | Bug Council |

### Агенты с Atlassian

| Агент | Инструменты |
|-------|-------------|
| `requirements-analyst` | `jira_get_issue`, `confluence_get_page` |

### Агенты с mcp-pgs-tool

| Агент | Инструменты |
|-------|-------------|
| `db-schema-reader` | `pg_list_schemas`, `pg_list_tables`, `pg_list_columns`, `pg_column_stats` |

---

## Bundled Tools (Базовые)

DevTeam также использует стандартные bundled tools (без MCP префикса):

| Инструмент | Описание |
|------------|----------|
| `read_file` | Чтение файлов |
| `edit` | Редактирование файлов |
| `write_file` | Запись файлов |
| `glob` | Поиск файлов по паттерну |
| `grep_search` | grep_search по содержимому |
| `agent` | Вызов суб-агентов |
| `bash` | Выполнение shell команд |
| `todo_write` | Управление задачами |
| `ask_user_question` | Интерактивные вопросы |
| `skill` | Вызов скилов |
| `list_directory` | list_directory директорий |

---

## Добавление Нового MCP Сервера

### Шаг 1: Добавить в `qwen-extension.json`

```json
"mcpServers": {
  "your-server": {
    "type": "stdio",
    "command": "npx",
    "args": ["-y", "@your/mcp-server"]
  }
}
```

### Шаг 2: Добавить инструменты в нужные агенты

В файле агента (например, `agents/kotlin-api-developer.md`):

```yaml
tools:
  - mcp__graphfocus__find_symbol
  - mcp__your-server__your_tool  # <-- добавить
```

### Шаг 3: Перезапустить Qwen Code

Новые инструменты станут доступны после перезапуска.

---

## Troubleshooting

### GraphFocus не работает

**Проверка установки**:
```bash
which graphfocus
graphfocus --version
```

**Проверка индекса**:
```bash
ls graphfocus-out/
```

**Пересоздание индекса**:
```bash
graphfocus analyze ./src
```

### mcp-pgs-tool ошибки

**Проверка подключения к PostgreSQL**:
```bash
psql -h localhost -U postgres -c "\\dt"
```

---

## Ссылки

- [GraphFocus GitHub](https://github.com/your/graphfocus)
- [mcp-pgs-tool](https://github.com/your/mcp-pgs-tool)
- [MCP Documentation](https://modelcontextprotocol.io)
- [DevTeam Architecture](../arch.md)
