# Migrating from Claude Code Plugin (v4.x) to Qwen Code Extension (v5.0)

If you previously used the DevTeam Claude Code plugin and are moving
to the Qwen Code extension, this guide covers the key changes.

## Installation

| Claude Code (4.x) | Qwen Code (5.0) |
|---|---|
| `/plugin marketplace add https://github.com/michael-harris/devteam` | (not needed; Qwen Code discovers extensions locally) |
| `/plugin install devteam@devteam-marketplace` | `qwen extensions install .` (from local clone) |
| `/plugin install /path/to/devteam` (local) | `qwen extensions install .` or `qwen extensions link .` (for dev) |
| `bash install-local.sh` (dev) | `bash install.sh` |

## Commands

| Old (Claude Code) | New (Qwen Code) |
|---|---|
| `/devteam:plan` | `/devteam:plan` (unchanged) |
| `/devteam:implement` | `/devteam:implement` (unchanged) |
| `/devteam:bug "..."` | `/devteam:bug "..."` (unchanged) |
| `/devteam:worktree-status` | `/devteam:worktree status` |
| `/devteam:worktree-list` | `/devteam:worktree list` |
| `/devteam:worktree-cleanup` | `/devteam:worktree cleanup` |
| `/devteam:merge-tracks` | `/devteam:worktree merge` |

The four worktree-related commands were consolidated into a single
`/devteam:worktree` command with subcommands.

## Environment variables

| Claude Code | Qwen Code | Notes |
|---|---|---|
| `CLAUDE_PLUGIN_ROOT` | `QWEN_PROJECT_DIR` | Resolves to the extension install dir |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` | (removed) | Qwen Code subagents are native |
| `CLAUDE_TOOL_NAME`, `CLAUDE_TOOL_INPUT` | (read from stdin JSON) | Use the new shim at `hooks/run-hook.sh` |
| `CLAUDE_OUTPUT`, `STOP_HOOK_MESSAGE` | (read from stdin JSON) | Same |
| `CLAUDE_SESSION_ID` | `QWEN_SESSION_ID` (new) | Set by Qwen Code in stdin |
| `DEVTEAM_LOG_LEVEL` | (unchanged) | Read by `scripts/state.sh` |

The `install.sh` hook merger is tolerant: scripts that read
the legacy env-var names via `hooks/run-hook.sh` continue to work
because the shim translates Qwen Code's stdin JSON to those vars.

## Manifest

| Claude Code | Qwen Code |
|---|---|
| `.claude-plugin/plugin.json` | `qwen-extension.json` (at root) |
| `.claude-plugin/marketplace.json` | (not needed; Qwen Code uses local discovery) |
| `settings.json` (plugin defaults) | (not needed; manifest IS the defaults) |

## Skills

| Claude Code | Qwen Code |
|---|---|
| `skills/<cmd>/SKILL.md` | `skills/<name>/SKILL.md` (Qwen validates per `docs/features/skills.md`) |
| Frontmatter: `name`, `description`, `model`, `allowed-tools`, `user-invocable`, `argument-hint`, `!`-shell-injections | Frontmatter: `name`, `description`, `priority` (optional) |
| Skills are model-invoked | Skills are model-invoked (unchanged) |

## Subagents

| Claude Code | Qwen Code |
|---|---|
| `agents/<category>/<name>.md` | `agents/<name>.md` (flat layout) |
| Frontmatter: `name`, `description`, `model: opus\|sonnet\|haiku`, `tools: Read, Edit, …`, `memory: project` | Frontmatter: `name`, `description`, `tools:` (list) |
| 127 agents in 24 categories | 18 curated agents in flat layout |
| `Task({ subagent_type, model, prompt })` | `agent({ subagent_type, prompt })` (no `model`) |
| Qwen Code picked model via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` | Qwen Code native subagents (no env var) |

### To re-enable a removed agent

See `README.md` → "Removed Agents & Migration" for the recipe. In
short: copy `legacy/claude-code/old-agents/<category>/<name>.md` to
`agents/<name>.md`, strip Claude-specific frontmatter, add Qwen
frontmatter, restart.

## Hooks

| Claude Code | Qwen Code |
|---|---|
| `hooks/hooks.json` (top-level) | `hooks/hooks-config.json` (fragment) merged into `~/.qwen/settings.json` via `install.sh` (shell + jq) |
| `hooks/run-hook.js` (Node.js wrapper) | `hooks/run-hook.sh` (bash shim) |
| Hook events: PreToolUse, PostToolUse, Stop, SubagentStart, SubagentStop, TaskCompleted, WorktreeCreate, WorktreeRemove, TeammateIdle, PreCompact, SessionStart, SessionEnd, Notification | Hook events: PreToolUse, PostToolUse, Stop, PreCompact, SessionStart, SessionEnd, Notification (Claude-specific events removed) |
| Hook types: `command`, `prompt` (LLM), `http` | Same (Qwen Code supports all three) — but devteam uses only `command` |
| Input via env vars (`CLAUDE_TOOL_NAME`, etc.) | Input via stdin JSON (shim translates for backward compat) |

## Filesystem layout

| Claude Code (4.x) | Qwen Code (5.0) |
|---|---|
| `.claude-plugin/` | (removed; replaced by `qwen-extension.json`) |
| `.claude/rules/` | (replaced by `QWEN.md`) |
| `commands/<name>.md` (flat) | `commands/devteam/<name>.md` (grouped) |
| `agents/<category>/<name>.md` | `agents/<name>.md` (flat, 18 active) |
| `skills/<name>/SKILL.md` | `skills/<name>/SKILL.md` (Qwen format) |
| `hooks/hooks.json` | `hooks/hooks-config.json` (fragment) |
| `agent-registry.json` | (removed; auto-discovery from filesystem) |
| `agent-registry.json` agent model field | (removed; Qwen Code picks model) |
| `settings.json` | (removed; manifest IS settings) |
| `.lsp.json` | (removed; Qwen Code uses its own LSP config) |
| `.mcp.json` | `qwen-extension.json` `mcpServers` field |
| (none) | `QWEN.md` (auto-loaded context) |

## Things that did NOT change

- Shell scripts in `scripts/*.sh` (state, events, db, schema)
- SQLite database in `.devteam/devteam.db` (portable)
- Hook scripts in `hooks/*.sh` (env-var contract preserved via shim)
- `.devteam/config.yaml` and other YAML configs (model names remain
  as documentation; can be ignored by Qwen Code)
- The 5-agent Bug Council workflow

## What was removed

- 109 specialist agents (mobile, devops, SRE, UX, security, etc.)
  — see `legacy/claude-code/old-agents/`
- LLM-prompt-typed hooks (use Qwen Code's native subagent system
  for the same capability)
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` env var
- Model tier names (`opus`, `sonnet`, `haiku`) in frontmatter
  (replaced with abstract `model_tier: low|medium|high` knob in
  `.devteam/config.yaml`)
- `scripts/update-agent-frontmatter.py` (Claude-Code-specific)

## Where to look for things

- **Plugin manifest** (was `.claude-plugin/plugin.json`) →
  `qwen-extension.json`
- **Default settings** (was `settings.json`) →
  inside `qwen-extension.json`
- **LSP config** (was `.lsp.json`) →
  use Qwen Code's `/lsp` to inspect configured servers
- **MCP config** (was `.mcp.json`) →
  `qwen-extension.json` `mcpServers` field
- **Path-specific rules** (was `.claude/rules/*.md`) →
  consolidate into `QWEN.md` (Qwen Code does not yet support
  path-gated rules via `paths:` in skills, but does honor it for
  skill activation — see `docs/features/skills.md` for details)
