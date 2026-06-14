#!/bin/bash
# DevTeam Hooks — for Qwen Code, use the root install.sh instead.
# This directory contains hook scripts used by Qwen Code.
# Hook configuration (hooks-config.json) is merged into ~/.qwen/settings.json
# by ../install.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "[devteam] Use the root install.sh to install the extension:"
echo ""
echo "  bash ${ROOT_DIR}/install.sh"
echo ""
echo "For hook documentation, see:"
echo "  ${SCRIPT_DIR}/README.md"
