---
name: verify-pipeline
description: Run the 12-step verification suite for the devteam Kotlin+Spring 3-stage pipeline. Use after creating/modifying agents, skills, commands, hooks, or config. Each step has explicit pass/fail criteria and can be run in isolation.
source: auto-skill
extracted_at: '2026-06-13T15:20:23.712Z'
---

# Verify Pipeline

Run the 12-step verification suite for the devteam extension. Each
step is independent and exits 0 on pass, non-zero on fail.

## When to use

- After adding/modifying any agent, skill, command, or hook file
- After changing `qwen-extension.json`, `QWEN.md`, `arch.md`, or `.devteam/config.yaml`
- Before committing changes
- When the user reports "the pipeline is broken" (run to localize)

## The 12 steps

Each step has a deterministic shell command. Run them individually
to isolate failures, or as a suite for the full check.

### V1: Submodule + sync (35 skills expected)

```bash
ls vendors/kotlin-backend-agent-skills/ 2>&1 | head -3
SKILL_COUNT=$(find skills -maxdepth 2 -name "SKILL.md" | wc -l | tr -d ' ')
[ "$SKILL_COUNT" = "35" ] && echo "OK" || echo "FAIL ($SKILL_COUNT)"
```

If FAIL, run `bash scripts/sync-kotlin-skills.sh` to re-populate.

### V2: Frontmatter (inline OR block `tools:`)

```bash
python3 -c "
import re, sys
from pathlib import Path
errors = []
TOOLS_RE = re.compile(r'^tools:\s*(\[[^\]]+\]|\s*$)', re.MULTILINE)
for f in Path('agents').glob('*.md'):
    text = f.read_text()
    m = re.match(r'^---\n(.*?)\n---', text, re.DOTALL)
    if not m: continue
    fm = m.group(1)
    if not re.search(r'^name:', fm, re.M): errors.append(f'{f}: no name')
    if not re.search(r'^description:', fm, re.M): errors.append(f'{f}: no description')
    if not TOOLS_RE.search(fm): errors.append(f'{f}: tools')
    if re.search(r'^model:\s*(opus|sonnet|haiku)', fm, re.M): errors.append(f'{f}: model')
if errors: print('FAIL'); sys.exit(1)
print('OK')
"
```

The regex accepts both `tools:` (YAML list on next lines) and
`tools: [a, b, c]` (inline). Rejects `model: opus|sonnet|haiku`.

### V2b: Skill references resolve

```bash
python3 -c "
import re, sys
from pathlib import Path
errors = []
for f in Path('agents').glob('*.md'):
    text = f.read_text()
    refs = set(re.findall(r'skills/([a-z][a-z0-9-]+)', text))
    for r in refs:
        if not (Path('skills') / r).is_dir():
            errors.append(f'{f}: skills/{r}/')
if errors: print('FAIL'); sys.exit(1)
print('OK')
"
```

Catches stale `skills/kotlin/<name>/` references (skills are now
flat in `skills/<name>/`).

### V3: Agent count (20-30 expected)

```bash
ACTUAL=$(find agents -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
[ "$ACTUAL" -ge 20 ] && [ "$ACTUAL" -le 30 ] && echo "OK ($ACTUAL)" || echo "FAIL ($ACTUAL)"
```

### V4: Hook idempotency (9 blocks, same before/after)

```bash
TEST_HOME=$(mktemp -d); mkdir -p "$TEST_HOME/.qwen"
echo '{}' > "$TEST_HOME/.qwen/settings.json"
HOME="$TEST_HOME" python3 lib/install-hooks.py --scope=user >/dev/null
C1=$(python3 -c "import json; print(sum(len(v) for v in json.load(open('$TEST_HOME/.qwen/settings.json')).get('hooks',{}).values()))")
HOME="$TEST_HOME" python3 lib/install-hooks.py --scope=user >/dev/null
C2=$(python3 -c "import json; print(sum(len(v) for v in json.load(open('$TEST_HOME/.qwen/settings.json')).get('hooks',{}).values()))")
[ "$C1" = "$C2" ] && [ -f "$TEST_HOME/.qwen/.devteam-installed" ] && echo "OK" || echo "FAIL"
rm -rf "$TEST_HOME"
```

### V5: `--skip-stage` validation (shell)

```bash
ERR=0
bash scripts/dry-run.sh --feature "X" --skip-stage banana 2>&1 | grep -q "not one of" || ERR=$((ERR+1))
bash scripts/dry-run.sh --feature "X" --skip-stage "analytics analytics" 2>&1 | grep -q "twice" || ERR=$((ERR+1))
bash scripts/dry-run.sh --feature "X" --skip-stage 2>&1 | grep -q "requires an argument" || ERR=$((ERR+1))
bash scripts/dry-run.sh --feature "X" --skip-stage "analytics,development" 2>&1 | grep -q "SKIPPED" || ERR=$((ERR+1))
[ "$ERR" = "0" ] && echo "OK" || echo "FAIL ($ERR errors)"
```

### V5b: `--skip-stage` validation (live prompt in `build.md`)

```bash
grep -q "VALID_STAGES\|not one of" commands/devteam/build.md && \
  grep -q "requires an argument\|twice" commands/devteam/build.md && \
  echo "OK" || echo "FAIL"
```

### V6: Predicates (hybrid + greenfield)

```bash
rm -rf /tmp/test-hybrid && mkdir -p /tmp/test-hybrid/src/main/kotlin && cd /tmp/test-hybrid && git init -q
bash /path/to/devteam/scripts/dry-run.sh --feature "X" 2>&1 | grep -q "code-archaeologist INCLUDED" && \
  H1=OK || H1=FAIL
cd /path/to/devteam
rm -rf /tmp/test-greenfield && mkdir -p /tmp/test-greenfield && cd /tmp/test-greenfield
bash /path/to/devteam/scripts/dry-run.sh --feature "X" 2>&1 | grep -q "code-archaeologist SKIPPED" && \
  G1=OK || G1=FAIL
[ "$H1" = "OK" ] && [ "$G1" = "OK" ] && echo "OK" || echo "FAIL"
```

### V6b: api-spec predicate (openapi.yml)

```bash
rm -rf /tmp/test-openapi && mkdir -p /tmp/test-openapi && echo "openapi: 3.0.0" > /tmp/test-openapi/openapi.yml && cd /tmp/test-openapi
bash /path/to/devteam/scripts/dry-run.sh --feature "X" 2>&1 | grep -q "api-spec-reader INCLUDED" && echo "OK" || echo "FAIL"
cd /path/to/devteam
```

### V7: `--dry-run` determinism

```bash
A=$(bash scripts/dry-run.sh --feature "Add OAuth" 2>&1)
B=$(bash scripts/dry-run.sh --feature "Add OAuth" 2>&1)
[ "$A" = "$B" ] && echo "OK" || { echo "FAIL"; diff <(echo "$A") <(echo "$B") | head -10; }
```

Two identical runs MUST produce identical output (no timestamps).

### V8: Stage-2 partition overlap-free

```bash
OUT=$(bash scripts/dry-run.sh --feature "X" --skip-stage "analytics testing" 2>&1)
ERR=0
echo "$OUT" | grep -q "owns:.*api/" || ERR=$((ERR+1))
echo "$OUT" | grep -q "owns:.*domain/" || ERR=$((ERR+1))
echo "$OUT" | grep -q "owns:.*application.*yml" || ERR=$((ERR+1))
echo "$OUT" | grep -q "owns:.*client/.*infrastructure" || ERR=$((ERR+1))
echo "$OUT" | grep -q "Overlaps: none" || ERR=$((ERR+1))
[ "$ERR" = "0" ] && echo "OK" || echo "FAIL ($ERR)"
```

### V9: Retry policy in dry-run

```bash
bash scripts/dry-run.sh --feature "X" 2>&1 | grep -q "Retry policy: per_agent=2" && echo "OK" || echo "FAIL"
```

### V9b: Failure report format

```bash
ERR=0
bash scripts/dry-run.sh --feature "X" --simulate-fail-stage=development 2>&1 | grep -q "STAGE 2 FAILED" || ERR=$((ERR+1))
bash scripts/dry-run.sh --feature "X" --simulate-fail-stage=development 2>&1 | grep -q "Failed agents (retries exhausted)" || ERR=$((ERR+1))
bash scripts/dry-run.sh --feature "X" --simulate-fail-stage=development 2>&1 | grep -q "Succeeded agents (output preserved)" || ERR=$((ERR+1))
[ "$ERR" = "0" ] && echo "OK" || echo "FAIL"
```

### V10: No Claude Code refs in active code

```bash
LEAKS=$(grep -rE "claude code|CLAUDE_PLUGIN_ROOT|/plugin install|/plugin marketplace" \
  --include="*.md" --include="*.sh" --include="*.py" --include="*.json" . 2>/dev/null \
  | grep -vE "^\./legacy/" | grep -vE "^\./CHANGELOG\.md" | grep -vE "^\./docs/MIGRATION_FROM_CLAUDE\.md" \
  | grep -vE "^\./arch\.md" | grep -vE "^\./README\.md" | grep -vE "^\./QWEN\.md" || true)
[ -z "$LEAKS" ] && echo "OK" || { echo "FAIL"; echo "$LEAKS" | head -3; }
```

Excluded paths (where Claude refs are LEGITIMATE):
- `legacy/` — archived v5.0 plugin
- `CHANGELOG.md` — references old env vars for migration
- `docs/MIGRATION_FROM_CLAUDE.md` — user-facing migration guide
- `arch.md`, `README.md`, `QWEN.md` — rewritten, should be clean

### V10b: English-only docs (no Cyrillic)

```bash
NON_ASCII=$(grep -P '[^\x00-\x7F]' arch.md README.md QWEN.md 2>/dev/null | wc -l | tr -d ' ')
[ "$NON_ASCII" = "0" ] && echo "OK" || echo "FAIL ($NON_ASCII non-ASCII lines)"
```

## Run all 12 in sequence

```bash
cd /path/to/devteam

# V1
SKILL_COUNT=$(find skills -maxdepth 2 -name "SKILL.md" | wc -l | tr -d ' ')
echo "V1: ${SKILL_COUNT} skills (expected 35)"

# V2, V2b, V3, V4 — see above

# V5-V10b — see above
```

## Diagnosing failures

| Step | Likely cause | Fix |
|---|---|---|
| V1 | Upstream submodule not initialized | `git submodule update --init --recursive && bash scripts/sync-kotlin-skills.sh` |
| V2 | New agent has wrong frontmatter (model:, tools: as CSV) | Edit the agent file, remove model, convert tools to YAML list |
| V2b | Agent references a skill that doesn't exist | Either create the skill or fix the path |
| V3 | Count too high (>30) | Look for stale agents in `legacy/old-agents/` that leaked back |
| V4 | Install script not idempotent | Check `lib/install-hooks.py` deep_merge_hooks dedup |
| V5 | dry-run.sh missing validation case | Add the missing `case` statement |
| V5b | build.md prompt missing keywords | Add the validation keywords to the body |
| V6/V6b | Predicates not detecting correctly | Check `is_hybrid_predicate` and `has_api_spec` in dry-run.sh |
| V7 | Random/timestamp in dry-run output | Remove any `date`/`uuid`/`RANDOM` from output |
| V8 | Agent prompt/body contains wrong path pattern | Check Stage-2 partition table in plan |
| V9 | Config.yaml `pipeline.retry.per_agent` mismatch | Update both config and dry-run.sh default |
| V9b | dry-run.sh `--simulate-fail-stage` flag not implemented | Add the branch |
| V10 | Stale reference in a file that should be excluded | Either exclude or rewrite the file |
| V10b | Cyrillic in rewritten doc | Replace with English equivalent |

## Related

- `arch.md` — full system architecture
- `legacy/claude-code/MIGRATION_REFERENCE.md` — env-vars mapping
- `.devteam/config.yaml` — pipeline + retry configuration
- `commands/devteam/build.md` — main user entry point
- `scripts/dry-run.sh` — the shell mirror this skill verifies
