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

---

## ⚠️ Perl Gotcha — `@` in Paths Strips Everything After It

**The issue:** perl's replacement side of `s///` is a Perl expression — `$` and `@` are interpolated as variables. If your path contains `@` (e.g., `/Users/dev/project @client/.devteam/hooks`), the `@client` is parsed as an undefined array and silently consumed as empty, stripping the path:

```bash
# WRONG — even though we switched to perl, path still gets mangled
PATH="/Users/dev/project @client/.devteam"
perl -pe "s|__HOOK_BASE__|${PATH}/hooks|g" config.json
# Output: "/Users/dev/project /.devteam/hooks"   ← "@client" gone!
```

This is silent — perl does not error, just produces wrong output. CI on Linux won't catch it.

**Two required fixes (both necessary):**

1. **Escape `\` and `@` in the path via bash parameter expansion BEFORE passing to perl:**
   ```bash
   PERL_ESCAPED_TARGET="${DEVTEAM_TARGET//\\/\\\\}"
   PERL_ESCAPED_TARGET="${PERL_ESCAPED_TARGET//@/\\@}"
   ```

2. **Use single quotes around the perl expression with the path concatenated outside** (so bash doesn't apply its own escaping, but more importantly so perl sees a literal `@` after we escape it):
   ```bash
   perl -pe 's|__HOOK_BASE__|'"${PERL_ESCAPED_TARGET}"'/hooks|g' "$CONFIG_FILE"
   ```

**Complete correct pattern:**

```bash
PERL_ESCAPED_TARGET="${DEVTEAM_TARGET//\\/\\\\}"
PERL_ESCAPED_TARGET="${PERL_ESCAPED_TARGET//@/\\@}"
HOOK_CONFIG="$(perl -pe 's|__HOOK_BASE__|'"${PERL_ESCAPED_TARGET}"'/hooks|g' "$CONFIG_FILE")"
```

**Why both fixes are needed:**

| Variant | Path with `@` result |
|---------|----------------------|
| `perl -pe "s\|x\|${P}\|g"` (double quotes, no escape) | `@` stripped — `@client` becomes empty |
| `perl -pe 's\|x\|'"${P}"'\|g'` (single quotes concat, no escape) | `@` STILL stripped — perl sees raw `@client` |
| `perl -pe 's\|x\|'"${ESCAPED}"'\|g'` with `\`-escaped `@` and `\` | Works — perl sees literal `@client` |

The escape must happen in bash *before* the string reaches perl. Once it's inside perl's replacement, there's no way to escape it back.

## Related Gotcha — Empty settings.json Breaks jq Merge

If `settings.json` exists but is empty (zero bytes or whitespace), `jq ... file.json` reads empty input and produces no output — the merged file ends up blank. Guard with:

```bash
EXISTING_CONFIG="$(cat "${TARGET}/settings.json" 2>/dev/null || true)"
if [ -z "$(printf '%s' "$EXISTING_CONFIG" | tr -d '[:space:]')" ]; then
    EXISTING_CONFIG="{}"
fi

# Pass to jq via --argjson (don't pass file arg; jq would re-read from disk)
jq -n --argjson existing "$EXISTING_CONFIG" --argjson newcfg "$HOOK_CONFIG" \
    'def deep_merge($a;$b): ...; deep_merge($existing; $newcfg)'
```

Use `jq -n` (null input) so jq doesn't try to read filter from stdin.

## When to Apply These Gotchas

- Any `install.sh` that substitutes paths containing `@` (project names with `@client`, etc.)
- Any script merging into an existing `settings.json` that may have been touched by another tool
- Any cross-platform config-injection script

## How to Test

```bash
# Verify @ preservation end-to-end:
TESTDIR="/tmp/test @project-$$"
mkdir -p "$TESTDIR"
bash install.sh "$TESTDIR"
grep -q "@project" "$TESTDIR/.qwen/settings.json" && echo "PASS" || echo "FAIL"
rm -rf "$TESTDIR"

# Verify empty-input guard:
echo -n "" > /tmp/test-settings.json
jq -n --argjson existing "{}" --argjson newcfg '{"hooks":{}}' \
    'def deep_merge($a;$b): if ($a|type)=="object" and ($b|type)=="object"
     then reduce ($b|keys[]) as $k ($a; if has($k) then .[$k] = deep_merge(.[$k]; $b[$k]) else .[$k] = $b[$k] end)
     else $b end; deep_merge($existing; $newcfg)'
# Should output: {"hooks":{}}
```
