#!/bin/bash
# DevTeam Qwen Code extension installer.
# Installs hooks, agents, commands, skills into target .qwen/ directory.
# Supports project-level (via project-path argument) and user-level (default) install.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="${PLUGIN_DIR}/hooks"
CONFIG_FILE="${PLUGIN_DIR}/hooks/hooks-config.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[devteam]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[devteam]${NC} $1"; }
log_error() { echo -e "${RED}[devteam]${NC} $1" >&2; }

# ============================================================================
# USAGE
# ============================================================================

usage() {
    cat <<EOF
Usage: bash install.sh [project-path]

Installs DevTeam into the target .qwen/ directory.

Arguments:
  project-path    Optional path to a project. If provided, installs into
                  <project-path>/.qwen/. If omitted, auto-detects:
                  - inside git repo: <cwd>/.qwen/
                  - outside git repo: ~/.qwen/

Examples:
  bash install.sh                        # user-level install
  bash install.sh /path/to/myproject    # project-level install
EOF
}

# ============================================================================
# PREREQUISITES
# ============================================================================

echo ""
echo "Checking prerequisites..."

MISSING=()

command -v git     >/dev/null 2>&1 || MISSING+=("git")
command -v jq      >/dev/null 2>&1 || MISSING+=("jq")
command -v python3 >/dev/null 2>&1 || MISSING+=("python3")

# uv is recommended but optional — only required for auto-installing
# the graphfocus MCP server. If missing, the install proceeds but
# graphfocus won't be configured automatically.
command -v uv >/dev/null 2>&1 && HAS_UV=1 || HAS_UV=0

if [ ${#MISSING[@]} -gt 0 ]; then
    log_error "missing required tools: ${MISSING[*]}"
    echo "  Install jq:       https://jqlang.github.io/jq/download/"
    echo "  Install python3:   https://www.python.org/downloads/"
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
JQ_VERSION=$(jq --version)
log_info "prerequisites OK (git, python${PYTHON_VERSION}, jq ${JQ_VERSION})"

if [ "$HAS_UV" -eq 0 ]; then
    log_warn "uv not found — graphfocus MCP server will not be auto-installed"
    log_warn "  Install uv: https://docs.astral.sh/uv/getting-started/installation/"
fi

# ============================================================================
# RESOLVE TARGET DIRECTORY
# ============================================================================

resolve_target() {
    local arg_path="$1"

    if [ -n "$arg_path" ]; then
        # Explicit path provided — user's intent
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

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

PROJECT_PATH="${1:-}"

if [ "${1:-}" == "--help" ] || [ "${1:-}" == "-h" ]; then
    usage
    exit 0
fi

TARGET="$(resolve_target "$PROJECT_PATH")"
SENTINEL="${TARGET}/.devteam-installed"

# .devteam/ location:
# - Project-level: <project>/.devteam/ (sibling to .qwen/)
# - User-level: ~/.qwen/.devteam/ (inside .qwen/)
if [ -n "$PROJECT_PATH" ]; then
    DEVTEAM_TARGET="$(realpath "$PROJECT_PATH")/.devteam"
else
    DEVTEAM_TARGET="${TARGET}/.devteam"
fi

# ============================================================================
# IDEMPOTENCY CHECK
# ============================================================================

if [ -f "$SENTINEL" ]; then
    log_info "already installed at ${TARGET} — run 'bash uninstall.sh${PROJECT_PATH:+ $PROJECT_PATH}' first to reinstall"
    exit 0
fi

# ============================================================================
# MCP SERVER PREREQUISITES (warn-only)
# ============================================================================

echo ""
echo "Checking MCP server prerequisites..."
if ! command -v npx >/dev/null 2>&1; then
    log_warn "npx (Node.js) not found — github and memory MCP servers will be unavailable"
    log_warn "  Install Node.js from https://nodejs.org/"
else
    log_info "MCP prerequisites OK (npx found)"
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
    log_warn "GITHUB_TOKEN not set — github MCP server will be unavailable"
else
    log_info "GITHUB_TOKEN is set"
fi

# ============================================================================
# GRAPHFOCUS MCP INSTALLATION
# ============================================================================
# Install graphfocus (knowledge graph for code analysis) into a dedicated
# virtual environment under <mcp-servers>/graphfocus/.venv. Self-contained
# — no system-wide Python pollution, no PATH conflicts. Idempotent: skip
# if already configured in either the global user-level or target settings.json.

echo ""
echo "Setting up graphfocus MCP server..."

# Resolve the mcp-servers/ directory based on install level.
if [ -n "$PROJECT_PATH" ]; then
    MCP_SERVERS_DIR="${DEVTEAM_TARGET}/mcp-servers"
else
    MCP_SERVERS_DIR="${HOME}/mcp-servers"
fi

# Where the venv lives and the shim inside it that we'll point MCP at.
GRAPHFOCUS_VENV_DIR="${MCP_SERVERS_DIR}/graphfocus/.venv"
GRAPHFOCUS_BIN="${GRAPHFOCUS_VENV_DIR}/bin/graphfocus"

GLOBAL_SETTINGS="${HOME}/.qwen/settings.json"
# TARGET settings.json may not exist yet — is_graphfocus_configured handles it.

is_graphfocus_configured() {
    local f="$1"
    [[ ! -f "$f" ]] && return 1
    # .mcpServers.graphfocus truthy → already configured
    if jq -e '.mcpServers.graphfocus // empty' "$f" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

GRAPHFOCUS_INSTALLED=false
GRAPHFOCUS_BIN_PATH=""  # absolute path to use in settings.json

if is_graphfocus_configured "$GLOBAL_SETTINGS"; then
    log_info "graphfocus MCP already configured in ${GLOBAL_SETTINGS} — skipping install"
    GRAPHFOCUS_INSTALLED=true
    GRAPHFOCUS_BIN_PATH="graphfocus"
elif is_graphfocus_configured "${TARGET}/settings.json"; then
    log_info "graphfocus MCP already configured in ${TARGET}/settings.json — skipping install"
    GRAPHFOCUS_INSTALLED=true
    GRAPHFOCUS_BIN_PATH="graphfocus"
elif [[ -x "$GRAPHFOCUS_BIN" ]]; then
    log_info "graphfocus venv already exists at ${GRAPHFOCUS_VENV_DIR}"
    GRAPHFOCUS_INSTALLED=true
    GRAPHFOCUS_BIN_PATH="$GRAPHFOCUS_BIN"
else
    if [ "$HAS_UV" -eq 0 ]; then
        log_warn "uv not found — cannot auto-install graphfocus"
        log_warn "  Install uv (https://docs.astral.sh/uv/) then run install.sh again"
        log_warn "  Or manually:"
        log_warn "    uv venv ${GRAPHFOCUS_VENV_DIR}"
        log_warn "    uv pip install --python ${GRAPHFOCUS_VENV_DIR}/bin/python 'graphfocus[all]'"
        GRAPHFOCUS_INSTALLED=false
    else
        log_info "installing graphfocus into venv at ${GRAPHFOCUS_VENV_DIR}..."
        mkdir -p "${MCP_SERVERS_DIR}/graphfocus"

        if uv venv "$GRAPHFOCUS_VENV_DIR" 2>&1 | tee /tmp/graphfocus-venv.log; then
            if uv pip install \
                --python "${GRAPHFOCUS_VENV_DIR}/bin/python" \
                --quiet \
                'graphfocus[all]' 2>&1 | tee /tmp/graphfocus-install.log; then
                if [[ -x "$GRAPHFOCUS_BIN" ]]; then
                    GRAPHFOCUS_INSTALLED=true
                    GRAPHFOCUS_BIN_PATH="$GRAPHFOCUS_BIN"
                    log_info "graphfocus installed: ${GRAPHFOCUS_BIN}"
                else
                    log_warn "pip install succeeded but ${GRAPHFOCUS_BIN} not found"
                fi
            else
                log_warn "uv pip install failed — see /tmp/graphfocus-install.log"
                log_warn "  Re-run, or install manually:"
                log_warn "    uv pip install --python ${GRAPHFOCUS_VENV_DIR}/bin/python 'graphfocus[all]'"
            fi
        else
            log_warn "uv venv creation failed — see /tmp/graphfocus-venv.log"
        fi
    fi
fi

if [[ "$GRAPHFOCUS_INSTALLED" == "true" ]]; then
    log_info "graphfocus mcp-servers directory: ${MCP_SERVERS_DIR}/graphfocus"

    # Drop a small README so the directory isn't empty and explains its role.
    cat > "${MCP_SERVERS_DIR}/graphfocus/README.md" <<EOF
# graphfocus MCP server

This directory is managed by DevTeam's install.sh. It is the
project- (or user-) level home for graphfocus-related artifacts.

graphfocus is installed in an isolated Python virtual environment at:
  ${GRAPHFOCUS_VENV_DIR}

The MCP server is invoked via the entry-point shim:
  ${GRAPHFOCUS_BIN}

To upgrade graphfocus:
\`\`\`bash
uv pip install --upgrade --python ${GRAPHFOCUS_VENV_DIR}/bin/python 'graphfocus[all]'
\`\`\`

To remove:
\`\`\`bash
rm -rf ${MCP_SERVERS_DIR}/graphfocus
\`\`\`
EOF
fi

# ============================================================================
# CREATE TARGET DIRECTORY
# ============================================================================

log_info "target: ${TARGET}"
mkdir -p "${TARGET}"

# ============================================================================
# COPY TO TARGET
# ============================================================================

echo ""
echo "Installing into ${TARGET}..."

# Copy agents, commands, skills to .qwen/
for dir in agents commands skills; do
    if [ -d "${PLUGIN_DIR}/${dir}" ]; then
        rm -rf "${TARGET}/${dir}"
        cp -r "${PLUGIN_DIR}/${dir}" "${TARGET}/${dir}"
        count=$(find "${TARGET}/${dir}" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
        log_info "  ${dir}/ — ${count} files"
    fi
done

# Create .devteam/ and copy hooks/, scripts/, config/
mkdir -p "${DEVTEAM_TARGET}"
rm -rf "${DEVTEAM_TARGET}/hooks" "${DEVTEAM_TARGET}/scripts" "${DEVTEAM_TARGET}/config"
cp -r "${PLUGIN_DIR}/hooks" "${DEVTEAM_TARGET}/hooks"
cp -r "${PLUGIN_DIR}/scripts" "${DEVTEAM_TARGET}/scripts"
cp -r "${PLUGIN_DIR}/config" "${DEVTEAM_TARGET}/config"

count_hooks=$(find "${DEVTEAM_TARGET}/hooks" -name '*.sh' -o -name '*.js' -o -name '*.ps1' 2>/dev/null | wc -l | tr -d ' ')
count_scripts=$(find "${DEVTEAM_TARGET}/scripts" -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')
count_configs=$(find "${DEVTEAM_TARGET}/config" -type f 2>/dev/null | wc -l | tr -d ' ')
log_info "  .devteam/hooks/ — ${count_hooks} scripts"
log_info "  .devteam/scripts/ — ${count_scripts} scripts"
log_info "  .devteam/config/ — ${count_configs} config files"

# ============================================================================
# MERGE HOOKS INTO settings.json
# ============================================================================

echo ""
echo "Installing hooks into ${TARGET}/settings.json..."

# Substitute __HOOK_BASE__ placeholder with absolute path.
# Use perl for cross-platform sed compatibility (macOS sed doesn't handle / in paths well).
# The replacement side of s/// in perl interpolates $ and @ as variables; a literal
# `@` in the path would be silently consumed as an (undefined) array, stripping
# everything from " @" onward. Escape \ and @ in the path before substituting.
PERL_ESCAPED_TARGET="${DEVTEAM_TARGET//\\/\\\\}"
PERL_ESCAPED_TARGET="${PERL_ESCAPED_TARGET//@/\\@}"
HOOK_CONFIG="$(perl -pe 's|__HOOK_BASE__|'"${PERL_ESCAPED_TARGET}"'/hooks|g' "$CONFIG_FILE")"

# Build the combined config to write into settings.json: hooks + (optional)
# mcpServers.graphfocus. Combining before the merge avoids two separate
# jq passes and produces a single atomic write.
#
# GRAPHFOCUS_BIN_PATH is the absolute path to the venv entry-point shim
# (set during the GRAPHFOCUS MCP INSTALLATION step above). It is fed
# through jq's --arg so any characters in the path — including spaces
# and "@" — are correctly JSON-escaped.
COMBINED_CONFIG="$HOOK_CONFIG"
if [[ "$GRAPHFOCUS_INSTALLED" == "true" ]]; then
    MCP_CONFIG=$(jq -n \
        --arg cmd "$GRAPHFOCUS_BIN_PATH" \
        '{mcpServers: {graphfocus: {type: "stdio", command: $cmd, args: ["mcp"]}}}')
    COMBINED_CONFIG=$(jq -s '.[0] + .[1]' \
        <(printf '%s' "$HOOK_CONFIG") \
        <(printf '%s' "$MCP_CONFIG")) || COMBINED_CONFIG="$HOOK_CONFIG"
fi

if [ ! -f "${TARGET}/settings.json" ]; then
    echo "$COMBINED_CONFIG" > "${TARGET}/settings.json"
    log_info "created ${TARGET}/settings.json"
else
    # Guard against an existing-but-empty settings.json — jq emits nothing on
    # empty input, which would corrupt the merged output. Treat whitespace-only
    # content as empty as well.
    EXISTING_CONFIG="$(cat "${TARGET}/settings.json" 2>/dev/null || true)"
    if [ -z "$(printf '%s' "$EXISTING_CONFIG" | tr -d '[:space:]')" ]; then
        EXISTING_CONFIG="{}"
    fi

    tmp_file="$(mktemp)"
    trap "rm -f '$tmp_file'" EXIT

    jq -n --argjson newcfg "$COMBINED_CONFIG" --argjson existing "$EXISTING_CONFIG" '
      def deep_merge($a; $b):
        if ($a | type) == "object" and ($b | type) == "object" then
          ($a | keys) as $akeys | ($b | keys) as $bkeys |
          ($akeys + $bkeys | unique) as $allkeys |
          $allkeys | map(
            . as $k |
            if ($a | has($k)) and ($b | has($k)) then
              {key: $k, value: deep_merge($a[$k]; $b[$k])}
            elif ($a | has($k)) then
              {key: $k, value: $a[$k]}
            else
              {key: $k, value: $b[$k]}
            end
          ) | from_entries
        else
          ($b // $a)
        end;
      deep_merge($existing; $newcfg)
    ' > "$tmp_file"

    mv "$tmp_file" "${TARGET}/settings.json"
    log_info "merged hooks into ${TARGET}/settings.json"
fi

# ============================================================================
# INITIALIZE STATE
# ============================================================================

echo ""
echo "Initializing state..."
mkdir -p "${TARGET}/scripts"
# Project-level: .devteam/ lives next to .qwen/ (sibling layout)
# User-level: .devteam/ lives inside .qwen/ (TARGET is ~/.qwen)
if [ -n "$PROJECT_PATH" ]; then
    STATE_ROOT="$PROJECT_PATH"
else
    STATE_ROOT="$TARGET"
fi
bash "${PLUGIN_DIR}/scripts/state-init.sh" "${STATE_ROOT}"

# ============================================================================
# CREATE SENTINEL
# ============================================================================

echo ""
echo "Creating sentinel..."
date +%Y-%m-%dT%H:%M:%S > "$SENTINEL"
echo "${TARGET}" >> "$SENTINEL"
log_info "created ${SENTINEL}"

# ============================================================================
# DONE
# ============================================================================

echo ""
echo "Installation complete!"
echo ""
echo "  Target:      ${TARGET}"
echo "  Hooks:       ${TARGET}/settings.json"
echo "  Agents:      ${TARGET}/agents/    ($(find "${TARGET}/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ') files)"
echo "  Commands:    ${TARGET}/commands/   ($(find "${TARGET}/commands" -name '*.md' 2>/dev/null | wc -l | tr -d ' ') files)"
echo "  Skills:      ${TARGET}/skills/     ($(find "${TARGET}/skills" -name '*.md' 2>/dev/null | wc -l | tr -d ' ') files)"
echo "  .devteam/:   ${DEVTEAM_TARGET}   (hooks, scripts, config, state)"
if [[ "$GRAPHFOCUS_INSTALLED" == "true" ]]; then
    echo "  graphfocus:  ${MCP_SERVERS_DIR}/graphfocus"
fi
echo ""
echo "Next steps:"
echo "  1. Restart Qwen Code to load the extension"
echo "  2. Verify: /skills (should show devteam skills)"
echo "  3. Verify: /agents manage (should show subagents)"
echo "  4. Verify: /devteam:status"
echo "  5. (Optional) Set GITHUB_TOKEN for GitHub MCP integration"
if [[ "$GRAPHFOCUS_INSTALLED" == "true" ]]; then
    echo "  6. (Optional) Run 'graphfocus analyze .' in your project to build the knowledge graph"
fi
