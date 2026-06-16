#!/bin/bash
# DevTeam Qwen Code Hook Shim
#
# Reads Qwen Code hook input from stdin (JSON), maps it to the legacy
# env-var contract that the existing 9 hook scripts in hooks/*.sh expect
# (CLAUDE_TOOL_NAME, CLAUDE_TOOL_INPUT, CLAUDE_OUTPUT, STOP_HOOK_MESSAGE),
# then invokes the appropriate legacy hook script.
#
# Why this shim exists: Qwen Code passes hook data via stdin JSON;
# the existing hooks/*.sh scripts were written for Claude Code's
# env-var-based input. This shim bridges the two without rewriting
# 9 scripts (~3000 lines of bash).

set -euo pipefail

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

# 2. Map Qwen Code fields -> legacy env vars using python3.
#    python3 handles edge cases (unicode, escapes) that grep/sed would mangle.
if [[ -n "$STDIN_JSON" ]] && command -v python3 >/dev/null 2>&1; then
  eval "$(python3 - "$STDIN_JSON" <<'PY'
import json, sys, shlex
try:
    d = json.loads(sys.argv[1])
except Exception:
    sys.exit(0)

def emit(k, v):
    if v is None:
        return
    if isinstance(v, (dict, list)):
        v = json.dumps(v, ensure_ascii=False)
    print(f"export {k}={shlex.quote(str(v))}")

# Common
emit("CLAUDE_SESSION_ID", d.get("session_id"))
emit("CLAUDE_CWD", d.get("cwd"))
emit("CLAUDE_TIMESTAMP", d.get("timestamp"))

# Tool events (PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest)
emit("CLAUDE_TOOL_NAME", d.get("tool_name"))
emit("CLAUDE_TOOL_INPUT", d.get("tool_input"))
emit("CLAUDE_TOOL_USE_ID", d.get("tool_use_id"))

# Stop / SubagentStop
emit("STOP_HOOK_MESSAGE", d.get("last_assistant_message"))
emit("CLAUDE_OUTPUT", d.get("last_assistant_message"))

# Notification: synthesize a tool_name for downstream scripts
if d.get("notification_type"):
    emit("CLAUDE_TOOL_NAME", "Notification")
    emit("CLAUDE_TOOL_INPUT", json.dumps({"type": d["notification_type"]}))

# Session
emit("CLAUDE_PERMISSION_MODE", d.get("permission_mode"))
emit("CLAUDE_SESSION_SOURCE", d.get("source"))
PY
)"
fi

# 3. Invoke the legacy hook
exec "$HOOK_SCRIPT"
