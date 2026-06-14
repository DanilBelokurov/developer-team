# Changelog

All notable changes to devteam are documented in this file.

## [5.0.0] — 2026-06-13 — Qwen Code Migration

### Changed
- **Migration to Qwen Code extension format.** The project is now a native
  Qwen Code extension installable via `qwen extensions install .` or
  `qwen extensions link .` (development).
- **Manifest**: `.claude-plugin/plugin.json` + `marketplace.json` →
  `qwen-extension.json` at repo root.
- **Subagents**: 127 agents in `agents/<category>/<name>.md` → 18 curated
  agents in flat `agents/<name>.md`. 109 specialized agents moved to
  `legacy/claude-code/old-agents/<category>/` and can be re-enabled
  selectively.
- **Skills**: `skills/<cmd>/SKILL.md` (Claude Code) → `skills/<name>/SKILL.md`
  (Qwen Code). Frontmatter simplified to `name`, `description`, `priority`.
  `model`, `allowed-tools`, `user-invocable`, `argument-hint` removed.
- **Slash commands**: `commands/<name>.md` (flat) → `commands/devteam/<name>.md`
  (grouped; invoked as `/devteam:name`).
- **Hooks**: `hooks/hooks.json` (top-level) + `hooks/run-hook.js`
  (cross-platform Node.js wrapper) → settings.json fragment
  (`hooks/hooks-config.json`) merged by `lib/install-hooks.py` + new
  `hooks/run-hook.sh` shim that converts Qwen Code's stdin JSON to the
  env-var contract the existing 9 hook scripts expect.
- **Environment variables**: `CLAUDE_PLUGIN_ROOT` → `QWEN_PROJECT_DIR`.
  `scripts/state.sh` falls back through both, then to `git rev-parse`.
- **Removed**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (replaced by
  Qwen Code's native subagent system via the `agent` tool).
- **Removed**: model tier names (`opus`, `sonnet`, `haiku`) from
  frontmatter. `model_tier: low|medium|high` is the abstract knob;
  Qwen Code picks the actual model.

### Removed
- `scripts/update-agent-frontmatter.py` — Claude-Code-specific. (0
  references found in the repo at migration time.)
- LLM-prompt-typed hooks (replaced with their functional equivalents in
  Qwen Code's native subagent system).
- `TeammateIdle`, `SubagentStart`, `SubagentStop`, `TaskCompleted`,
  `WorktreeCreate`, `WorktreeRemove` hook events — Qwen Code handles
  these natively.

### Migration aid
- `legacy/claude-code/MIGRATION_REFERENCE.md` — table of all
  env-vars, file paths, and format differences for users porting
  workflows back to Claude Code or contributing upstream.
- `docs/MIGRATION_FROM_CLAUDE.md` — user-facing guide for adapting
  existing Claude Code plugin workflows to the Qwen Code extension.

## [4.x] — Claude Code plugin (legacy)

The 4.x series was a Claude Code marketplace plugin. Original files
are preserved under `legacy/claude-code/` for reference.
