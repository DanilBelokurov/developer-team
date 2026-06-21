---
name: devteam-install-workflow
description: Project-level + user-level install/uninstall workflow with sentinel-based idempotency and absolute hook paths
source: auto-skill
extracted_at: '2026-21T19:07:35.961Z'
---

# DevTeam Install/Uninstall Workflow

## Problem

Qwen Code extensions need to install into a `.qwen/` directory. Two scenarios:
- **Project-level**: each project gets its own `.qwen/`, isolated from others
- **User-level**: one shared `.qwen/` in `$HOME`

The install script must:
1. Accept an optional project path argument
2. Auto-detect the target when no argument is given
3. Be idempotent (second run = no-op)
4. Use absolute paths for hook commands in `settings.json`
5. Mirror the same target resolution in uninstall

## Initial Setup: vendors/ (optional, for syncing upstream skills)

`vendors/kotlin-backend-agent-skills/` is a **git submodule** containing 25 upstream Kotlin skills from https://github.com/yalishevant/kotlin-backend-agent-skills. It is **NOT used by `install.sh`** — it only feeds `sync-kotlin-skills.sh`.

**Data flow:**

```
vendors/kotlin-backend-agent-skills/   ← upstream (git submodule)
         ↓ scripts/sync-kotlin-skills.sh
skills/kotlin/                         ← local copy (in repo)
         ↓ install.sh
.qwen/skills/                          ← install target
```

**Setup (one-time, before install):**

```bash
git submodule update --init --recursive
bash scripts/sync-kotlin-skills.sh
# Output: "Done. 25 skills synced"
```

**When `vendors/` is safe to delete:**

- ✅ `skills/kotlin/` already contains all 25 synced skill files
- ✅ You do not plan to update skills from upstream

- ❌ `skills/kotlin/` is empty (fresh clone) — you need `vendors/` to populate it first

**After deleting `vendors/`:**

```bash
# To update skills from upstream again, re-add the submodule:
git submodule add https://github.com/yalishevant/kotlin-backend-agent-skills vendors/kotlin-backend-agent-skills
git submodule update --init --recursive
bash scripts/sync-kotlin-skills.sh
```

## Solution

### Target Resolution (shared between install.sh and uninstall.sh)

```bash
resolve_target() {
    local arg_path="$1"

    if [ -n "$arg_path" ]; then
        # Explicit path = user's intent
        echo "$(realpath "$arg_path")/.qwen"
        return
    fi

    # Auto-detect: inside git repo?
    if git -C . rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "$(pwd)/.qwen"
        return
    fi

    # Fallback: user-level
    echo "${HOME}/.qwen"
}
```

### Sentinel at Target Level

Store the install timestamp + target path inside the target `.qwen/`:

```bash
TARGET="$(resolve_target "$PROJECT_PATH")"
SENTINEL="${TARGET}/.devteam-installed"

# Idempotency check
if [ -f "$SENTINEL" ]; then
    log_info "already installed at ${TARGET}"
    exit 0
fi

# Write sentinel
date +%Y-%m-%dT%H:%M:%S > "$SENTINEL"
echo "${TARGET}" >> "$SENTINEL"
```

### Absolute Paths in settings.json

Use a `__HOOK_BASE__` placeholder in the source config file. Substitute with the real absolute path during install using `perl` (not `sed` — macOS sed breaks on `/` in paths):

```bash
# hooks-config.json contains:
#   "command": "__HOOK_BASE__/run-hook.sh pre-tool-use-hook"

# install.sh substitutes:
HOOK_CONFIG="$(perl -pe "s|__HOOK_BASE__|${TARGET}/hooks|g" config.json)"
```

### State Directory Layout

For project-level installs, the runtime state directory (`.devteam/`) lives **next to** `.qwen/` (sibling layout), not inside it:

```
<project>/
├── .qwen/              ← install target
│   ├── agents/
│   ├── commands/
│   ├── skills/
│   ├── hooks/
│   ├── settings.json   ← absolute hook paths
│   └── .devteam-installed
└── .devteam/           ← runtime state (sibling to .qwen/)
    └── state/
```

For user-level installs, `.devteam/` lives **inside** `~/.qwen/`.

### Uninstall Mirrors Install

```bash
# Same resolve_target() function
TARGET="$(resolve_target "$PROJECT_PATH")"
SENTINEL="${TARGET}/.devteam-installed"

if [ ! -f "$SENTINEL" ]; then
    log_error "not installed at ${TARGET}"
    exit 1
fi

# Remove in order: sentinel first (marks install as incomplete on failure)
rm -f "$SENTINEL"
rm -rf "${TARGET}/"{agents,commands,skills,hooks}/

# Remove hooks from settings.json
if [ -f "${TARGET}/settings.json" ]; then
    jq 'delpaths([["hooks"]])' "${TARGET}/settings.json" > tmp && mv tmp "${TARGET}/settings.json"
fi

# State: sibling for project-level, inside for user-level
if [ -n "$PROJECT_PATH" ]; then
    rm -rf "${PROJECT_PATH}/.devteam"
else
    rm -rf "${TARGET}/.devteam"
fi
```

## When to Apply

- Any Qwen Code extension that supports project-level installation
- Any multi-project tool that needs isolated per-project config
- Scripts that need to be idempotent and support both global and local install

## Key Design Decisions

| Decision | Choice | Why |
|---|---|---|
| Sentinel location | Inside target `.qwen/` | Self-contained, moves with the install |
| Path substitution | `perl -pe` not `sed` | macOS BSD sed breaks on `/` in replacement |
| State layout | Sibling `.devteam/` | Keeps install artifact separate from runtime state |
| Unused sentinel | No-op on reinstall | Clear message + exit 0, not error |
