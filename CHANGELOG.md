# Changelog

All notable changes to devteam are documented in this file.

## [6.3.0] — 2026-06-15 — Project-level install

### Added
- **Project-level installation.** `install.sh [project-path]` installs
  into `<project>/.qwen/` instead of `~/.qwen/`, isolating each project
  from others.
- **Auto-detection.** Without an argument, `install.sh` resolves target as:
  - inside git repo → `<cwd>/.qwen/`
  - outside git → `~/.qwen/`
- **Sentinel at target level.** `<target>/.devteam-installed` stores
  install timestamp + target path.
- **`uninstall.sh [project-path]`** with matching target resolution
  and clean removal of project-level state.
- **Semgrep MCP server** added (9 tools: scan, SCA, AST, custom rules, etc.)
- **Semgrep quality gate** — security scan on changed files, blocks HIGH/CRITICAL findings

### Changed
- **`install.sh`** completely rewritten:
  - accepts optional `project-path` argument
  - uses `perl` instead of `sed` for cross-platform path substitution
  - deep-merges hooks into `<target>/settings.json` with absolute paths
  - idempotent (second run is no-op)
- **`uninstall.sh`** rewritten with project-level target resolution
  and removal of sibling `.devteam/` state for project-level installs
- **`hooks/hooks-config.json`**: replaced `$QWEN_PROJECT_DIR` with
  `__HOOK_BASE__` placeholder (substituted by install.sh with absolute path)

### Fixed
- macOS `sed` incompatibility with `/` in paths (switched to `perl`)
- sentinel location ambiguity (now always inside target `.qwen/`)

### Migration
If upgrading from v6.2 with a user-level install:
1. Old sentinel `~/.devteam-installed` is ignored — reinstall is safe
2. Run `bash install.sh` to refresh hooks with absolute paths
3. For project-level: `bash install.sh /path/to/project`

## [6.2.0] — 2026-06-14 — File-based state (no SQLite)

### Changed (BREAKING)
- **Removed SQLite dependency.** All state now stored in Markdown files
  under `.devteam/state/`. No more `sqlite3` binary requirement.
- `scripts/db-init.sh` → `scripts/state-init.sh` (mkdir + touch only)
- `scripts/schema.sql` → `scripts/state-structure.md` (documentation;
  v6.1 schema files archived at `legacy/claude-code/sqlite-schema/`)
- `scripts/state.sh` rewritten to use file ops (atomic via mkdir-based
  locking, POSIX-portable, no `flock` dependency)
- `scripts/lib/progress.sh` removed (was SQLite-era helper)
- `install.sh` updated to call `state-init.sh` instead of `db-init.sh`

### NOT changed (zero-risk regression)
- `hooks/*.sh` (9 scripts) — source `state.sh` unchanged; all 35
  function names preserved (`set_kv_state`, `get_kv_state`, `set_state`,
  `get_state`, `start_session`, `end_session`, etc.)
- `agents/pipeline-orchestrator.md` and other 17 agents — call
  `set_kv_state` / `get_kv_state` unchanged
- `commands/devteam/build.md` and other 16 commands — source
  `state.sh` unchanged
- `install.sh` — hooks merge to `~/.qwen/settings.json` (shell + jq, no Python),
  doesn't depend on state storage
- `scripts/dry-run.sh` — shell mirror, no state touches

### Migration from v6.1
If upgrading from v6.1 with existing `.devteam/devteam.db`:
1. Recommended: run `bash scripts/state-migrate-v61-to-v62.sh` (one-time
   conversion script; details in `scripts/state-structure.md`)
2. Alternative: delete `.devteam/devteam.db` and start fresh

### Why
- **No external binary** — works on any system (Windows, minimal Linux,
  containers)
- **Human-readable** — `cat` the file, edit in any IDE
- **Git-trackable** — diff state changes in PRs
- **Trivial backup** — `cp -r .devteam/state backup/`
- **Zero dependencies** — pure POSIX shell

Trade-offs accepted: slower for high-frequency reads, no SQL query
power, no transactional semantics. For DevTeam's scale, negligible.

## [6.1.0] — 2026-06-14 — Human-in-the-Loop (HITL) gate

### Added
- **Human-in-the-Loop (HITL) gate after Stage 1 (Analytics)**.
  Pipeline pauses for human approval before Stage 2 (Development)
  starts. Always-on for `/devteam:build`. 4 options: Approve,
  Request changes (re-run Stage 1), Edit analysis.md manually,
  Abort pipeline.
- New `session_state` KV values: `stage.development.status` adds
  `"awaiting_approval"`. New keys: `hitl_paused_at`, `hitl_action`
  (`approve|edit|request_changes|abort`), `hitl_resolved_at`,
  `analysis_path`.
- New `pipeline.hitl` config section in `.devteam/config.yaml`
  (default: `enabled: true`).
- New dry-run flags: `--simulate-hitl-{approve,reject,edit,abort}`.
- New verifications: V11 (HITL pause + 4 actions) and V12 (build.md
  prompt contains HITL keywords).
- `agents/pipeline-orchestrator.md` now documents the HITL gate logic
  with `ask_user_question` invocation pattern and resume logic.
- `instr.md` and `arch.md` updated with HITL sections.

### Behavior
- After Stage 1 completes, `pipeline-orchestrator` calls
  `ask_user_question` with 4 options (Approve / Request changes /
  Edit / Abort).
- On Approve or Edit: `stage.development.status = "pending"`, Stage 2
  proceeds.
- On Request changes: re-runs Stage 1, then re-prompts HITL.
- On Abort: sets `pipeline.active = "false"`, does NOT emit
  `EXIT_SIGNAL: true` (Stop hook does not block exit, but the
  pipeline halts at user request).
- HITL is auto-skipped when Stage 2 is skipped or analysis is empty.
- Resume logic: if Qwen Code restarts while HITL is paused, the
  orchestrator reads `hitl_action` from KV and resumes accordingly.

## [6.0.0] — 2026-06-13 — Kotlin + Spring backend pipeline

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
- **Hooks**: `hooks/hooks-config.json` (fragment) merged by `install.sh`
  (shell + jq, no Python) + new `hooks/run-hook.sh` shim that converts
  Qwen Code's stdin JSON to the env-var contract the existing 9 hook
  scripts expect.
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
