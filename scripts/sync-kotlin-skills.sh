#!/bin/bash
# Sync all skills from vendors/kotlin-backend-agent-skills/.agents/skills/
# to skills/<name>/SKILL.md (top level).
#
# Upstream layout (per upstream README):
#   .agents/skills/<skill-name>/SKILL.md
#   .agents/skills/<skill-name>/agents/openai.yaml  (ignored — OpenAI-specific)
#
# We only copy SKILL.md into our skills/kotlin/<name>/SKILL.md.
# Qwen Code discovers skills/ via qwen-extension.json.
set -euo pipefail

VENDOR="${VENDOR:-vendors/kotlin-backend-agent-skills}"
DEST="skills/kotlin"

if [ ! -d "$VENDOR" ]; then
  echo "ERR: $VENDOR not found. Run:"
  echo "    git submodule add https://github.com/yalishevant/kotlin-backend-agent-skills vendors/kotlin-backend-agent-skills"
  echo "    git submodule update --init --recursive"
  exit 1
fi

# Try the canonical path first (.agents/skills/), fall back to skills/ for older layouts
SRC=""
if [ -d "$VENDOR/.agents/skills" ]; then
  SRC="$VENDOR/.agents/skills"
elif [ -d "$VENDOR/skills" ]; then
  SRC="$VENDOR/skills"
else
  echo "ERR: no skills/ or .agents/skills/ directory in $VENDOR. Upstream layout may have changed."
  exit 1
fi

mkdir -p "$DEST"
count=0
skipped=0
for skill_dir in "$SRC"/*/; do
  [ -d "$skill_dir" ] || continue
  name=$(basename "$skill_dir")
  if [ ! -f "$skill_dir/SKILL.md" ]; then
    echo "WARN: $name has no SKILL.md, skipping"
    skipped=$((skipped+1))
    continue
  fi
  mkdir -p "$DEST/$name"
  cp "$skill_dir/SKILL.md" "$DEST/$name/SKILL.md"
  count=$((count+1))
  echo "synced: $name"
done

echo ""
echo "Done. $count skills synced, $skipped skipped."
echo "Source: $SRC"
echo "Dest:   $DEST/<skill-name>/SKILL.md"
