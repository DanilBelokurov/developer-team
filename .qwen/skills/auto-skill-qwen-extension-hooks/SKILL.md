---
name: qwen-extension-hooks
description: Configure Qwen Code hooks in extension manifest instead of separate config files
source: auto-skill
extracted_at: '2026-06-15T10:35:53.902Z'
---

# Qwen Extension Hooks: Manifest vs External Config

## The Problem

When installing Qwen Code extensions, hooks defined in external `hooks-config.json` files merged into `~/.qwen/settings.json` via shell scripts fail because `$QWEN_PROJECT_DIR` doesn't resolve outside of an installed extension.

## The Solution

Put hooks directly in `qwen-extension.json` under `settings.hooks`:

```json
{
  "name": "my-extension",
  "version": "1.0.0",
  "settings": {
    "hooks": {
      "PreToolUse": [...],
      "Stop": [...],
      "SessionStart": [...]
    }
  }
}
```

This way:
- `qwen extensions install .` installs everything (hooks, agents, commands, skills)
- `$QWEN_PROJECT_DIR` resolves correctly because it's a registered extension
- No separate `install.sh` needed for hooks

## When to Use

- New Qwen Code extensions → always use `settings.hooks` in manifest
- Legacy extensions with `hooks-config.json` + shell installer → migrate to manifest
- `$QWEN_PROJECT_DIR` not resolving → likely not installed as extension

## Installation Flow After Migration

```bash
# 1. Prerequisites check (optional, keep if needed)
bash install.sh

# 2. Install as extension (hooks auto-included)
qwen extensions install .
```

## Files to Clean Up After Migration

- `hooks/hooks-config.json` — delete (now in manifest)
- `hooks/install.sh` — delete or simplify (hooks no longer need shell merge)
- `install.sh` — simplify to just prerequisites/state init

## Verification

After installation, hooks should appear in `~/.qwen/settings.json` with `$QWEN_PROJECT_DIR` resolved to the extension directory.
