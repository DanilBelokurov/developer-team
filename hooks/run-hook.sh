#!/bin/bash
# DevTeam Qwen Code Hook Shim
#
# Reads Qwen Code hook input from stdin (JSON), maps it to the QWEN_*
# env-var contract, then invokes the appropriate hook script.
#
# Environment variables exported:
#   QWEN_SESSION_ID     - session identifier
#   QWEN_CWD            - current working directory
#   QWEN_TIMESTAMP      - hook timestamp
#   QWEN_TOOL_NAME      - tool name (PreToolUse, PostToolUse, etc.)
#   QWEN_TOOL_INPUT     - tool input JSON
#   QWEN_TOOL_USE_ID    - unique tool use identifier
#   QWEN_TOOL_RESPONSE   - tool response (PostToolUse)
#   QWEN_LAST_MESSAGE    - last assistant message (Stop hook)
#   QWEN_STOP_MESSAGE    - alias for last message (Stop hook)
#   QWEN_PERMISSION_MODE - permission mode
#   QWEN_SESSION_SOURCE  - session source (startup, resume, etc.)
#   QWEN_NOTIFICATION_TYPE - notification type (for Notification events)

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

# 2. Map Qwen Code fields -> QWEN_* env vars using python3.
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

# Common fields (all events)
emit("QWEN_SESSION_ID", d.get("session_id"))
emit("QWEN_CWD", d.get("cwd"))
emit("QWEN_TIMESTAMP", d.get("timestamp"))

# Tool events (PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest)
emit("QWEN_TOOL_NAME", d.get("tool_name"))
emit("QWEN_TOOL_INPUT", d.get("tool_input"))
emit("QWEN_TOOL_USE_ID", d.get("tool_use_id"))
# PostToolUse uses tool_response (not tool_result!)
emit("QWEN_TOOL_RESPONSE", d.get("tool_response"))

# Stop / SubagentStop - last assistant message
emit("QWEN_LAST_MESSAGE", d.get("last_assistant_message"))
emit("QWEN_STOP_MESSAGE", d.get("last_assistant_message"))

# Notification events
if d.get("notification_type"):
    emit("QWEN_NOTIFICATION_TYPE", d.get("notification_type"))

# Session events
emit("QWEN_PERMISSION_MODE", d.get("permission_mode"))
emit("QWEN_SESSION_SOURCE", d.get("source"))

# Subagent events
emit("QWEN_AGENT_ID", d.get("agent_id"))
emit("QWEN_AGENT_TYPE", d.get("agent_type"))
PY
)"
fi

# 3. Invoke the hook
exec "$HOOK_SCRIPT"
