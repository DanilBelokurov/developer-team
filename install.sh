#!/bin/bash
# DevTeam Qwen Code extension installer.
# Thin wrapper: delegates hook merging to lib/install-hooks.py and
# state init to scripts/state-init.sh (v6.2 — file-based state).
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing devteam Qwen Code extension from: $PLUGIN_DIR"
echo ""

# 1. Core prerequisites
MISSING=()
command -v python3 >/dev/null 2>&1 || MISSING+=("python3")
command -v git      >/dev/null 2>&1 || MISSING+=("git")
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "ERROR: missing required tools: ${MISSING[*]}"
  exit 1
fi
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "Core prerequisites OK (python${PYTHON_VERSION}, git)"

# 2. MCP server prerequisites (warn-only — extension still loads without them)
echo ""
echo "Checking MCP server prerequisites..."
if ! command -v npx >/dev/null 2>&1; then
  echo "  WARN: npx (Node.js) not found — github and memory MCP servers will be unavailable"
  echo "       Install Node.js from https://nodejs.org/ to enable them"
else
  echo "  OK: npx found (Node.js $(node --version 2>/dev/null || echo 'unknown'))"
fi
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "  WARN: GITHUB_TOKEN env var not set — github MCP server will be unavailable"
  echo "       Set it with: export GITHUB_TOKEN=<your_personal_access_token>"
else
  echo "  OK: GITHUB_TOKEN is set"
fi
echo "  (memory MCP server requires no auth and will work if npx is available)"

# 3. Install hooks (Python, idempotent, sentinel-file based)
echo ""
echo "Installing hooks into ~/.qwen/settings.json..."
SCOPE_FLAG="--scope=user"
[ "${1:-}" = "--scope=project" ] && SCOPE_FLAG="--scope=project"
python3 "$PLUGIN_DIR/lib/install-hooks.py" "$SCOPE_FLAG"

# 4. Initialize state (v6.2 — file-based, no SQLite)
echo ""
echo "Initializing state..."
bash "$PLUGIN_DIR/scripts/state-init.sh"

# 5. Done
echo ""
echo "Installation complete!"
echo ""
echo "  Skills:    $PLUGIN_DIR/skills/    (13 skills)"
echo "  Agents:    $PLUGIN_DIR/agents/    (18 subagents)"
echo "  Commands:  $PLUGIN_DIR/commands/devteam/  (17 commands)"
echo ""
echo "Next steps:"
echo "  1. Restart Qwen Code to load the extension"
echo "  2. Verify: /skills (should show devteam skills)"
echo "  3. Verify: /agents manage (should show 18 subagents)"
echo "  4. Verify: /devteam:status (initializes .devteam/devteam.db)"
echo "  5. (Optional) Set GITHUB_TOKEN for GitHub MCP integration"
