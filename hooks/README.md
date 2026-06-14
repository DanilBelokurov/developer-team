# DevTeam Hook Scripts

Qwen Code hooks that enable autonomous execution, session persistence,
and quality enforcement.

## Overview

These hooks integrate with Qwen Code's hook system to provide:

- Autonomous execution until `EXIT_SIGNAL: true`
- Session memory persistence (SQLite via `scripts/state.sh`)
- State preservation across context compaction
- Anti-abandonment enforcement (`persistence-hook.sh` on `idle_prompt`)
- Scope validation and enforcement
- Dangerous command blocking
- Quality gate detection (post-tool-use)
- Stop-hook enforcement (blocks session exit without completion signal)

## Quick Start

### Qwen Code extension installation (recommended)

When DevTeam is installed as a Qwen Code extension (via
`qwen extensions install .` or `qwen extensions link .`), all hooks
are configured automatically through `hooks/hooks-config.json` →
merged into `~/.qwen/settings.json` by `lib/install-hooks.py`.

```bash
# Install
bash install.sh

# Or for dev workflow (live symlink)
qwen extensions link .

# Or one-shot
qwen extensions install .
```

All hook paths use `$QWEN_PROJECT_DIR` (Qwen Code resolves this
to the extension install directory).

### Hook event reference

| Event | Used by | Purpose |
|---|---|---|
| `PreToolUse` (Edit\|Write, Bash) | `pre-tool-use-hook.sh` | Scope check, dangerous-command block |
| `PostToolUse` (Edit\|Write, Bash) | `post-tool-use-hook.sh` | Track changes, detect gates |
| `Stop` (`*`) | `stop-hook.sh` | Block exit w/o `EXIT_SIGNAL: true` |
| `PreCompact` (manual\|auto) | `pre-compact.sh` | Save state to SQLite |
| `SessionStart` (startup\|resume) | `session-start.sh` | Init session |
| `SessionEnd` (`*`) | `session-end.sh` | Finalize session |
| `Notification` (idle_prompt) | `persistence-hook.sh` | Anti-abandonment |

### Exit codes (Qwen Code hook contract)

- `0` — success, continue
- `2` — **blocking error**, stderr shown to model
- other — non-blocking, execution continues

### Input contract

Qwen Code passes hook input as JSON via stdin. The shim at
`hooks/run-hook.sh` parses stdin and exports legacy env vars
(`CLAUDE_TOOL_NAME`, `CLAUDE_TOOL_INPUT`, etc.) so the existing
9 hook scripts continue to work.

## Hook Scripts

| Script | Purpose |
|---|---|
| `pre-tool-use-hook.sh` | Validates scope, blocks dangerous commands, warns on circuit breaker |
| `post-tool-use-hook.sh` | Detects quality gate results from bash output, tracks file changes |
| `stop-hook.sh` | Allows exit only when `EXIT_SIGNAL: true` is in the last message |
| `pre-compact.sh` | Saves state to `.devteam/devteam.db` before conversation compaction |
| `session-start.sh` | Initializes or resumes session in SQLite |
| `session-end.sh` | Finalizes session, calculates costs |
| `persistence-hook.sh` | Detects abandonment language on `idle_prompt`, re-engages |
| `scope-check.sh` | Helper for `pre-tool-use-hook.sh` (validates file paths against task scope) |
| `run-hook.sh` | Shim: maps Qwen Code stdin JSON → legacy env vars |

## Configuration

`hooks-config.json` is the source of truth for which events fire
which scripts. Merged into `~/.qwen/settings.json` by
`lib/install-hooks.py`. The merged config is idempotent: re-running
`bash install.sh` is a no-op.

## Troubleshooting

- Hooks don't fire? Check `~/.qwen/settings.json` has a `hooks` key
  and `~/.qwen/.devteam-installed` sentinel exists
- Stop hook blocking legitimate exit? Ensure your last message
  includes `EXIT_SIGNAL: true`
- Persistence hook false-positive? Adjust forbidden phrases in
  `.devteam/config.yaml` under `anti_abandonment.forbidden_phrases`
