---
name: cross-platform-path-substitution
description: Use perl instead of sed for path substitution in shell scripts — macOS sed breaks on / in replacement string
source: auto-skill
extracted_at: '2026-06-15T18:18:20.791Z'
---

# Cross-Platform Path Substitution in Shell Scripts

## Problem

`install.sh` scripts that substitute paths into config files using `sed` break silently on **macOS** because BSD/macOS `sed` does not handle `/` characters inside the replacement string, even when escaped:

```bash
# BROKEN on macOS — "bad flag in substitute command: 'U'"
TARGET="/Users/user/my project/.qwen"
sed "s/__HOOK_BASE__/${TARGET}\/hooks/g" config.json
```

The error appears only at runtime, not in tests run on Linux CI.

## Solution

Use **`perl`** with an alternate delimiter (`|`) instead of `/`. Perl is available on macOS by default and handles any character in replacement strings:

```bash
TARGET="/Users/user/my project/.qwen"
perl -pe "s|__HOOK_BASE__|${TARGET}/hooks|g" config.json
```

## When to Apply

- Any `install.sh` / `setup.sh` that injects absolute paths into JSON config files
- Any script that reads a template and substitutes a path containing `/`
- **Always prefer `perl -pe`** over `sed` for path substitution in portable scripts

## Alternative: Bash Parameter Expansion

For simple cases, bash `${var//pattern/replacement}` avoids external tools entirely:

```bash
TARGET="/Users/user/.qwen"
CONFIG="${CONFIG//__HOOK_BASE__/${TARGET}\/hooks}"   # but escaping / in bash is also painful
```

Perl is the most reliable cross-platform solution.
