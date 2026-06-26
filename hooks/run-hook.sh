#!/bin/bash
# DevTeam Qwen Code Hook Shim (v6.5 — no python3 dependency)
#
# Reads Qwen Code hook input from stdin (JSON), maps it to the legacy
# env-var contract that hook scripts expect
# (QWEN_TOOL_NAME, QWEN_TOOL_INPUT, QWEN_OUTPUT, STOP_HOOK_MESSAGE),
# then invokes the appropriate hook script.
#
# Why this shim exists: Qwen Code passes hook data via stdin JSON;
# the hook scripts were written for Claude Code's env-var-based input.
# This shim bridges the two without rewriting all hooks.
#
# H4 fix: the previous implementation spawned `python3` on every hook
# invocation (~50-100 ms cold start, hundreds of calls per session). We
# now use `jq` (already required elsewhere in the project) which starts
# in ~5 ms. If jq is missing entirely, we fall back to a pure-bash
# extractor that handles the small set of fields used by the hooks.

set -uo pipefail

HOOK_NAME="${1:-}"
if [[ -z "$HOOK_NAME" ]]; then
  echo "Usage: run-hook.sh <hook-name>" >&2
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/${HOOK_NAME}.sh"
if [[ ! -f "$HOOK_SCRIPT" ]]; then
  echo "[run-hook] Hook script not found: $HOOK_SCRIPT" >&2
  exit 0
fi

# 1. Read stdin into a JSON string (don't fail on empty stdin)
STDIN_JSON=""
if [[ ! -t 0 ]]; then
  STDIN_JSON="$(cat || true)"
fi

if [[ -n "$STDIN_JSON" ]]; then
  if command -v jq &>/dev/null; then
    # H4 fix: jq is already required by hook-common.sh and install.sh,
    # so it's safe to depend on it. Single invocation, sub-millisecond
    # once warm — replaces ~50-100 ms of python3 startup per hook.
    while IFS='=' read -r key value; do
      [[ -z "$key" ]] && continue
      printf 'export %s=%q\n' "$key" "$value"
    done < <(printf '%s' "$STDIN_JSON" | jq -r '
        def emit($k; $v): if $v == null then empty else [$k, ($v | tostring)] | @tsv end;

        emit("QWEN_SESSION_ID";    .session_id);
        emit("QWEN_CWD";           .cwd);
        emit("QWEN_TIMESTAMP";     .timestamp);
        emit("QWEN_TOOL_NAME";     .tool_name);
        emit("QWEN_TOOL_INPUT";    .tool_input);
        emit("QWEN_TOOL_USE_ID";   .tool_use_id);
        emit("STOP_HOOK_MESSAGE";    .last_assistant_message);
        emit("QWEN_OUTPUT";        .last_assistant_message);
        emit("QWEN_PERMISSION_MODE"; .permission_mode);
        emit("QWEN_SESSION_SOURCE";  .source);

        if .notification_type then
          emit("QWEN_TOOL_NAME";  "Notification");
          ("QWEN_TOOL_INPUT=\( {type: .notification_type} | tostring )" | @tsv)
        else empty end
    ')
  else
    # Pure-bash fallback: extract the few string fields the hooks use.
    # Sufficient for the common case; not exhaustive JSON coverage.
    emit_field() {
      local key="$1"
      local value
      value=$(printf '%s' "$STDIN_JSON" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -1)
      [[ -n "$value" ]] && printf 'export %s=%q\n' "QWEN_${key^^}" "$value"
    }
    emit_field session_id
    emit_field cwd
    emit_field timestamp
    emit_field tool_name
    emit_field last_assistant_message
    if [[ -n "$STDIN_JSON" ]] && grep -q '"notification_type"' <<< "$STDIN_JSON"; then
      local ntype
      ntype=$(printf '%s' "$STDIN_JSON" | sed -n 's/.*"notification_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
      printf 'export QWEN_TOOL_NAME=%q\n' "Notification"
      printf 'export QWEN_TOOL_INPUT=%q\n' "{\"type\":\"$ntype\"}"
    fi
  fi
fi

# 3. Invoke the legacy hook
exec "$HOOK_SCRIPT"