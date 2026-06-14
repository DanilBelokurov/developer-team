# Contributing to DevTeam

Thank you for your interest in contributing to DevTeam for Qwen Code.

## Development Setup

```bash
git clone https://github.com/michael-harris/devteam.git
cd devteam
bash install.sh
qwen extensions link .   # for live development
```

Prerequisites: Python 3.7+, sqlite3, git, optional Node.js + npx for MCP servers.

## Project Structure

```
devteam/
├── qwen-extension.json      # Extension manifest
├── QWEN.md                  # Auto-loaded context for the model
├── commands/devteam/        # Slash commands (16)
├── skills/                  # Skill files (12)
├── agents/                  # Subagent definitions (18)
├── hooks/                   # Hook scripts (9 .sh + run-hook.sh shim)
├── lib/install-hooks.py     # Python hook merger
├── scripts/                 # State, events, DB, schema
├── tests/                   # Test suite
├── examples/                # Usage examples
├── docs/                    # User and developer documentation
└── legacy/claude-code/      # Original Claude Code files (archive)
```

## Adding a Subagent

1. Choose a kebab-case name (e.g. `database-optimizer`).
2. Create `agents/<name>.md` with the frontmatter template:

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

   **Required frontmatter fields** (validated by Qwen Code, see
   `docs/features/skills.md` for the equivalent skill rules):
   - `name` — kebab-case, unique
   - `description` — what the agent does and when to use it
   - `tools` — list of tool names the agent can use

3. Body: write the agent's role, capabilities, process, and output format
   in clear Markdown. Qwen Code will read this verbatim and use it as the
   subagent's system prompt.

4. Test by invoking `/agents manage` in Qwen Code, or by asking a
   question that matches the description — the model should delegate.

## Adding a Slash Command

1. Create `commands/devteam/<command-name>.md`:

   ```markdown
   ---
   description: One-line description shown in /help.
   argument-hint: [required] [--flag <value>]
   ---

   # /devteam:command-name

   ## Your Process
   ...
   ```

2. Validated fields:
   - `description` — required
   - `argument-hint` — optional; for UI hints only

3. The command becomes available as `/devteam:command-name`.

## Adding a Skill

1. Create `skills/<skill-name>/SKILL.md`:

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

2. Validated fields (see `docs/features/skills.md`):
   - `name` — kebab-case, unique, validated against
     `/^[\p{L}\p{N}_:.-]+$/u`
   - `description` — non-empty
   - `priority` — optional finite number

3. Skills are **model-invoked**: Qwen Code activates them automatically
   when the description matches the user's request. Users can also run
   `/skills <name>` to invoke explicitly.

## Adding a Hook

1. Create `hooks/<event-name>.sh` (or `.ps1` for Windows).
2. The script receives input from Qwen Code via stdin (JSON). If you
   need the legacy env-var contract (`CLAUDE_TOOL_NAME`, etc.), invoke
   through `hooks/run-hook.sh` which maps Qwen Code's stdin JSON to those
   env vars automatically.
3. Exit codes:
   - `0` — success, continue
   - `2` — blocking error; stderr is shown to the model
   - other — non-blocking error; execution continues
4. Add a fragment to `hooks/hooks-config.json` describing when the hook
   fires (event, matcher, type=command, command).
5. Test by triggering the event and inspecting the hook's output.

## Code Style

- Shell scripts: `set -euo pipefail`, `local` for function vars,
  snake_case functions, UPPER_SNAKE_CASE constants.
- Python: PEP 8, type hints, stdlib-only (no external deps for
  `lib/install-hooks.py`).
- Markdown: clear imperative language, code fences for commands, no
  Claude Code references (use `$QWEN_PROJECT_DIR`, `qwen extensions …`).

## Tests

```bash
bash tests/run-tests.sh                                  # existing shell tests
python3 -c 'from lib.install_hooks import deep_merge_hooks; …'  # unit test
bash install.sh                                          # twice — second is no-op
```

## Pull Request Process

1. Create a feature branch: `git checkout -b feature/<name>`
2. Make your changes
3. Run `bash install.sh` twice to verify hook merge idempotency
4. Commit with descriptive messages
5. Open a PR

## Reference

- **Architecture**: [`arch.md`](arch.md) — detailed system
  architecture (layers, request lifecycle, Task Loop, Bug Council,
  anti-abandonment, data model, state machines, design trade-offs).
- Full agent index: `agents/` (18 subagents)
- Full command index: `commands/devteam/` (17 slash commands)
- Detailed docs: `docs/`

## License

By contributing, you agree that your contributions will be licensed
under the MIT License (see `LICENSE`).
