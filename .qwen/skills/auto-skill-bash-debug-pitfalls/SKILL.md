---
name: bash-debug-pitfalls
description: Debugging set -euo pipefail failures in DevTeam bash scripts
source: auto-skill
extracted_at: '2026-06-15T04:46:36.687Z'
---

# Bash `set -euo pipefail` Debugging Patterns

Lessons from debugging the v6.2 file-based state migration test suite.

---

## 1. `ls | head -1` exits 1 when no files match

**Symptom:** Function works in isolation but fails when run under `set -euo pipefail` with no visible error message.

**Root cause:** `ls <glob>` returns exit code 1 when the glob pattern matches no files. This is not an error to the OS — it's the documented behavior. Under `set -e`, the script exits immediately. With the `ERR` trap active, the trap fires but `on_error` may not echo the line number depending on context.

**Fix:** Always add `|| true` to `ls | head -1` pipelines that may have no matches:

```bash
# Before (fails with set -e when no files match):
latest_run=$(ls -t "$AGENT_RUNS_DIR"/*.md 2>/dev/null | head -1)

# After:
latest_run=$(ls -t "$AGENT_RUNS_DIR"/*.md 2>/dev/null | head -1 || true)
```

**Why the `|| true` is inside the command substitution, not outside:** `|| true` must be part of the pipeline so the pipeline as a whole always exits 0. Putting it outside (`$(...) || true`) also works but the pipeline itself can still fail.

---

## 2. `SCRIPT_DIR` variable shadowing from `source`

**Symptom:** `setup_test_db` works on the first call but subsequent calls in other test functions get wrong paths (e.g., `ROOT=scripts/.test-devteam` instead of `tests/.test-devteam`).

**Root cause:** `state.sh` contains `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` as a plain variable assignment (not `local`). When sourced, it overwrites the test runner's `$SCRIPT_DIR`. Bash has no scoping — `source` runs in the current shell and assignments are global.

**Fix:** Save and restore the caller's variable around `source`:

```bash
test_state_management() {
    local _saved_script_dir="$SCRIPT_DIR"
    source "$PROJECT_ROOT/scripts/state.sh"
    SCRIPT_DIR="$_saved_script_dir"
    # ... rest of test
}
```

**Why `local _saved_script_dir` works:** It captures the caller's value before `source` overwrites it, and restores it after.

---

## 3. `local` used outside a function

**Symptom:** Error message `bash: line N: local: can only be used in a function`.

**Root cause:** In a script or subshell context, `local` is only valid inside a function. The error fires and the variable doesn't get the local scope — other commands in the same pipeline or subsequent lines may still see the unassigned variable.

**Fix:** Ensure all shell logic that uses `local` is inside a function definition. If testing line-by-line in a script (not a function), omit `local`.

---

## 4. `readonly` re-declaration via `source`

**Symptom:** `readonly variable` error when a script is sourced twice, or when sourcing order changes.

**Root cause:** `readonly VAR=...` cannot be re-declared in the same shell session. If `common.sh` declares `readonly VALID_SESSION_FIELDS=(...)` and then `state.sh` sources `common.sh` which sources it again, the second `readonly` declaration fails.

**Fix:** Add an idempotency guard in every script that uses `readonly`:

```bash
if [ -n "${_COMMON_SH_SOURCED:-}" ]; then return 0; fi
_COMMON_SH_SOURCED=1
```

For color/constant variables that may be declared by multiple scripts:

```bash
[[ -z "${COLOR_GREEN:-}" ]] && readonly COLOR_GREEN='\033[0;32m'
```

**Why `[[ -z "${VAR:-}" ]] && readonly` works:** It checks if the variable is empty/unset before declaring it readonly. The `:-` expansion avoids "unbound variable" under `set -u`.

---

## 5. `((++VAR))` under `set -e`

**Symptom:** `((++TESTS_RUN))` causes script exit unexpectedly.

**Root cause:** `((expr))` returns exit code 1 when the expression evaluates to 0 (false). Postfix `((++TESTS_RUN))` on a line by itself means the increment is the last command — if TESTS_RUN starts at 0, `((++0))` evaluates to `((1))` which is 1 (truthy) — this is actually OK. But if the counter starts at -1 or if the prefix form is used, it can exit 1 under `set -e`. Best practice: use `((++VAR)) || true` or prefix form `((++VAR))` (prefix avoids the return-code issue for zero start values).

**Fix:** Use postfix `((++VAR))` for positive-starting counters, or add `|| true`:

```bash
((++TESTS_RUN)) || true  # always safe
```

---

## 6. Isolating failures with targeted debug

When a failure is hard to pinpoint:

```bash
# Step through function line-by-line in a subshell
( set -euo pipefail; log_agent_completed "test" "sonnet" "[]" 100 50 5 )
echo "rc=$?"

# Test exact pipeline
( set -euo pipefail; ls -t "$AGENT_RUNS_DIR"/*.md 2>/dev/null | head -1 )
echo "ls+head rc=$?"

# Override ERR trap for visibility
trap 'echo "ERR at line $LINENO rc=$?" >&2' ERR
```

The subshell isolates the failure from the parent context and allows the `ERR` trap to fire and report the correct line.

---

## 7. `source` overwrites caller's variables silently

**Symptom:** A function that sets `SCRIPT_DIR` (or any variable name used by the caller) breaks subsequent code that depends on the caller's value. The error is silent — no error message, just wrong behavior.

**Root cause:** Bash `source` runs in the current shell. Assignments to non-local variables (without `local` keyword) are global. If `state.sh` sets `SCRIPT_DIR="$(dirname ...)"` and the test runner also uses `$SCRIPT_DIR`, the test runner's value is overwritten for all subsequent code in the same shell session.

**Fix:** Save and restore around any `source` that may set global variables:

```bash
test_state_management() {
    local _saved_script_dir="$SCRIPT_DIR"
    source "$PROJECT_ROOT/scripts/state.sh"
    SCRIPT_DIR="$_saved_script_dir"
    # ... rest of test
}
```

**Pattern to apply:** Whenever sourcing a script that is not under your direct control (like `state.sh`, `events.sh`), save any variables the caller uses that might be reassigned by the sourced script. Common culprits: `SCRIPT_DIR`, `ROOT`, `DEVTEAM_DIR`, `PROJECT_ROOT`.

**Prevention:** Scripts that are meant to be sourced should declare their own variable names with `local` or use namespaced prefixes (e.g., `_DT_ROOT_` instead of `ROOT`).

---

## 8. Common ERR trap patterns

```bash
# In common.sh — always returns 0 so set -e doesn't re-trigger
on_error() {
    local line_no="$1" error_code="$2"
    log_error "Error on line $line_no (exit code: $error_code)" "trap"
}

setup_error_trap() {
    trap 'on_error ${LINENO} $?' ERR
}
```

The `return 0` (or no return) in `on_error` is critical — otherwise the trap itself triggers another ERR, potentially creating a loop.
