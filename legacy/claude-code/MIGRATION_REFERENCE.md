# Claude Code → Qwen Code Migration Reference

This is a detailed technical reference for porting code, configs, or
custom workflows between the v4.x Claude Code plugin and the v5.0
Qwen Code extension. It is the canonical counterpart to
`docs/MIGRATION_FROM_CLAUDE.md` (the user-facing guide).

## File-by-file mapping

| Claude Code file/dir | Qwen Code file/dir | Notes |
|---|---|---|
| `.claude-plugin/plugin.json` | `qwen-extension.json` | Different schema, see below |
| `.claude-plugin/marketplace.json` | (removed) | Qwen Code does not use a marketplace manifest in the same way |
| `settings.json` (plugin defaults) | (removed) | Default settings live in the manifest |
| `agent-registry.json` | (removed) | Agents auto-discovered from `agents/` |
| `commands/<name>.md` (flat) | `commands/<group>/<name>.md` | Grouping via subdir |
| `skills/<name>/SKILL.md` | `skills/<name>/SKILL.md` | Same path; frontmatter differs |
| `agents/<category>/<name>.md` | `agents/<name>.md` | Flat layout; curated to 18 |
| `agents/<category>/<name>.md` (deprecated) | `legacy/claude-code/old-agents/<category>/<name>.md` | 109 agents archived |
| `hooks/hooks.json` | `hooks/hooks-config.json` | Fragment merged into `~/.qwen/settings.json` |
| `hooks/run-hook.js` (Node) | `hooks/run-hook.sh` (bash) | Translates Qwen Code stdin JSON to legacy env vars |
| `hooks/<name>.sh` | `hooks/<name>.sh` (unchanged) | Same scripts; new shim bridges env-var contract |
| `hooks/<name>.ps1` | (kept for Windows users) | Same scripts |
| `.claude/rules/*.md` (path-specific) | (consolidate into `QWEN.md`) | Qwen Code does not yet support path-gated rules natively; all rules load together |
| `templates/interview-questions.yaml` | `legacy/claude-code/templates/` | Archived; was referenced by old `devteam:plan` Claude-style |
| `install-local.sh` | `install.sh` | Renamed and reimplemented |
| `agent-registry.json` (model field) | (removed) | Model picked by Qwen Code |
| `scripts/update-agent-frontmatter.py` | (removed) | Claude-Code-specific; 0 references found |
| `.lsp.json` | (removed) | Use Qwen Code's `/lsp` configuration |
| `.mcp.json` | `qwen-extension.json` `mcpServers` | Inline in manifest |
| `CLAUDE.md` (the original file) | (none — there was no Claude Code equivalent) | Qwen Code has its own `QWEN.md` |
| `CLAUDE.md` (legacy) | `legacy/claude-code/` (none — never existed) | n/a |

## Manifest schema differences

### Claude Code: `.claude-plugin/plugin.json`

```json
{
  "name": "devteam",
  "version": "4.0.0",
  "description": "...",
  "author": {"name": "..."},
  "homepage": "...",
  "repository": "...",
  "license": "MIT",
  "keywords": ["..."]
}
```

### Qwen Code: `qwen-extension.json`

```json
{
  "name": "devteam",
  "version": "5.0.0",
  "description": "...",
  "mcpServers": {
    "github": {...},
    "memory": {...}
  },
  "contextFileName": "QWEN.md",
  "commands": "commands",
  "skills": "skills",
  "agents": "agents"
}
```

Note: Qwen Code's manifest focuses on **discovery** (which dirs to scan)
rather than metadata. The Qwen Code source for field definitions is
`docs/extension/introduction.md:182-198` and
`docs/extension/getting-started-extensions.md:269`.

## Frontmatter field mapping

### Subagents (agents/<name>.md)

| Claude Code field | Qwen Code field | Notes |
|---|---|---|
| `name` | `name` | Required, kebab-case |
| `description` | `description` | Required |
| `model: opus\|sonnet\|haiku` | (removed) | Qwen Code picks model |
| `tools: Read, Edit, Write, Glob, Grep, Bash, Task` | `tools: [read_file, edit, write_file, glob, grep_search, bash, agent]` | One tool per line, lowercase, snake_case |
| `memory: project` | (removed) | Qwen Code has its own memory system |

### Skills (skills/<name>/SKILL.md)

| Claude Code field | Qwen Code field | Notes |
|---|---|---|
| `name` | `name` | Validated: `/^[\p{L}\p{N}_:.-]+$/u` |
| `description` | `description` | Required |
| `priority` | `priority` | Both; Qwen Code added as numeric field |
| `model` | (removed) | Not used for skills |
| `allowed-tools` | (removed) | Skills don't take tools |
| `user-invocable: true` | (removed) | All skills are model-invoked by default; user invokes via `/skills <name>` |
| `argument-hint` | (removed) | Not used in skill frontmatter (only commands) |
| `!` shell injection (in body) | (removed) | No shell injection in skills; use the `bash` tool from the agent |

### Commands (commands/<group>/<name>.md)

| Claude Code field | Qwen Code field | Notes |
|---|---|---|
| `description` | `description` | Required |
| `argument-hint` | `argument-hint` | Optional, both use it |
| `!` shell injection (in body) | (removed) | Use the `bash` tool |
| `model: opus` | (removed) | Not used for commands |
| `allowed-tools: Read, Edit, ...` | (removed) | Commands don't restrict tools |

## Hook event mapping

| Claude Code event | Qwen Code event | Notes |
|---|---|---|
| `PreToolUse` | `PreToolUse` | Same |
| `PostToolUse` | `PostToolUse` | Same |
| `PreToolUse` (LLM prompt type) | (removed) | Use Qwen Code's native subagent system |
| `PostToolUseFailure` | (removed in v4; may be added) | n/a |
| `Stop` | `Stop` | Same |
| `Notification` (matcher: `idle_prompt`) | `Notification` (matcher: `idle_prompt`) | Same |
| `PreCompact` | `PreCompact` | Same |
| `SessionStart` | `SessionStart` | Same |
| `SessionEnd` | `SessionEnd` | Same |
| `SubagentStart` | (removed) | Qwen Code handles natively |
| `SubagentStop` | (removed) | Qwen Code handles natively |
| `TaskCompleted` | (removed) | Qwen Code handles natively |
| `WorktreeCreate` | (removed) | Qwen Code has its own worktree feature |
| `WorktreeRemove` | (removed) | Same |
| `TeammateIdle` | (removed) | Claude-specific |
| `PermissionRequest` | (added in Qwen Code) | Not in original plugin |
| `TodoCreated`, `TodoCompleted` | (Qwen Code) | n/a |
| `UserPromptSubmit` | (Qwen Code) | n/a |
| `StopFailure` | (Qwen Code) | n/a |

## Env-var mapping (used by hooks/*.sh)

| Claude Code env var | Qwen Code stdin field | Notes |
|---|---|---|
| `CLAUDE_TOOL_NAME` | `tool_name` | String |
| `CLAUDE_TOOL_INPUT` | `tool_input` | Object (JSON-encoded) |
| `CLAUDE_OUTPUT` | `last_assistant_message` | String |
| `STOP_HOOK_MESSAGE` | `last_assistant_message` | String (same field, different var) |
| `CLAUDE_TOOL_USE_ID` | `tool_use_id` | String |
| `CLAUDE_SESSION_ID` | `session_id` | String |
| `CLAUDE_CWD` | `cwd` | String |
| `CLAUDE_TIMESTAMP` | `timestamp` | ISO 8601 string |
| `CLAUDE_PERMISSION_MODE` | `permission_mode` | Enum |
| `CLAUDE_SESSION_SOURCE` | `source` | For SessionStart |
| `CLAUDE_OUTPUT_TOKEN_COUNT` | (not exposed) | n/a |

The shim at `hooks/run-hook.sh` does the mapping automatically. If
you write new hooks, prefer reading the stdin JSON directly.

## Path mappings

| Claude Code | Qwen Code | Notes |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}` | `${QWEN_PROJECT_DIR}` | Resolves to extension install dir |
| `scripts/state.sh` | (unchanged) | Now also auto-detects `DEVTEAM_ROOT` |
| `scripts/events.sh` | (unchanged) | |
| `scripts/db-init.sh` | (unchanged) | |
| `scripts/schema.sql` | (unchanged) | |
| `.devteam/devteam.db` | (unchanged) | SQLite, gitignored |
| `.devteam/plans/<plan-id>/` | (unchanged) | |
| `.devteam/checkpoints/` | (unchanged) | |
| `.devteam/logs/` | (unchanged) | |

## Adding back Claude Code features

If you need a feature that was removed in the migration and want
to restore it (e.g., an LLM-prompt hook for a specific guard), the
recommended path is:

1. For removed agents: copy from `legacy/claude-code/old-agents/`
   back to `agents/`, transform frontmatter (see README).
2. For removed hooks: implement as a skill (model-invoked) instead.
   Example: instead of a `prompt` hook for "block dangerous bash
   commands", create a `security-review` skill that the model uses
   before invoking bash.
3. For `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`-style parallel
   execution: use Qwen Code's `/fork` command or `agent` tool with
   multiple invocations.

## Versioning

DevTeam 5.0.0+ is Qwen Code only. The Claude Code 4.x line is
preserved in `legacy/claude-code/` but receives no further updates.
