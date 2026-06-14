#!/bin/bash
# DevTeam Qwen Code extension uninstaller.
# Removes hooks from ~/.qwen/settings.json (or .qwen/settings.json
# with --scope=project). Does NOT remove the extension files themselves;
# use 'qwen extensions uninstall devteam' for that.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"

SCOPE_FLAG="--scope=user"
[ "${1:-}" = "--scope=project" ] && SCOPE_FLAG="--scope=project"

python3 "$PLUGIN_DIR/lib/install-hooks.py" --uninstall "$SCOPE_FLAG"

echo ""
echo "Note: extension files at the install path were NOT removed."
echo "Run 'qwen extensions uninstall devteam' to fully remove the extension."
echo "Run 'qwen extensions disable devteam' to keep files but stop loading."
