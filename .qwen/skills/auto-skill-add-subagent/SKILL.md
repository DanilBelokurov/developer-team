---
name: add-subagent
description: Procedure to add a new subagent to the devteam 3-stage pipeline. Use when the user wants to add a new specialist (e.g., a new language-specific developer, a new Bug Council member, or a new orchestrator) or to re-enable a legacy agent from legacy/claude-code/old-agents/. Covers frontmatter conventions, tools selection, file placement, partition rules, and post-creation verification.
source: auto-skill
extracted_at: '2026-06-14T13:00:55.260Z'
---

# Add Subagent

Procedure to add a new subagent to the devteam Qwen Code extension.
A "subagent" is a specialized AI invoked by the model via
`agent({ subagent_type: "<name>" })` and visible in `/agents manage`.

## When to use

Activate this skill when the user wants to:

- ✅ Add a new specialist (e.g., `kotlin-frontend-engineer`, `graphql-architect`)
- ✅ Re-enable a deprecated agent from `legacy/claude-code/old-agents/<category>/<name>.md`
- ✅ Add a new orchestrator (e.g., a new stage-orchestrator)
- ✅ Add a new Bug Council member
- ✅ Add a new cross-cutting agent (e.g., `kotlin-quality-gate-enforcer`)

**Do NOT use this skill** for:

- ❌ Adding a slash command — see `commands/devteam/<name>.md` directly
- ❌ Adding a skill — create `skills/<name>/SKILL.md` directly
- ❌ Modifying an existing agent — use `edit` tool on the existing file

## Process

### Step 1: Determine the agent's role and group

| Group | When | Example |
|---|---|---|
| Orchestrator | Coordinates a stage, dispatches sub-agents, no implementation | `pipeline-orchestrator`, `analytics-orchestrator` |
| Stage 1 (Analytics) | Reads code/schema/spec, produces structured analysis | `requirements-analyst`, `db-schema-reader` |
| Stage 2 (Development) | Writes Kotlin/Spring code in a file partition | `kotlin-api-developer` |
| Stage 3 (Testing) | Writes JUnit/Testcontainers/WireMock tests | `kotlin-unit-test-engineer` |
| Cross-cutting | Enforces quality gates, scope, requirements | `kotlin-quality-gate-enforcer` |
| Bug Council | Diagnoses complex bugs (5 specialists) | `root-cause-analyst` |

### Step 2: Choose the file path

All agents live in **flat layout** in `agents/<name>.md`:

```bash
# Correct
agents/kotlin-frontend-engineer.md

# WRONG (do not use subdirs)
agents/frontend/kotlin-frontend-engineer.md   # NO
```

**If re-enabling from legacy**: copy from `legacy/claude-code/old-agents/<category>/<name>.md`
to `agents/<name>.md` (you may keep the original in legacy for reference).

### Step 3: Write frontmatter

**Required fields** (validated by Qwen Code):

```yaml
---
name: <kebab-case-name>             # required: kebab-case, unique
description: "<one-line>"            # required: when to use this agent
tools:                                # required: YAML list (not CSV)
  - read_file
  - write_file
  - edit
  - glob
  - grep_search
  - bash
  - agent
---
```

**Tool selection guide**:

| Agent type | Required tools | Why |
|---|---|---|
| Read-only analyst (e.g., `db-schema-reader`) | `read_file, glob, grep_search` | No file writes |
| Code writer (e.g., `kotlin-api-developer`) | `read_file, write_file, edit, glob, grep_search, bash` | Writes Kotlin code, runs Gradle |
| Test writer (e.g., `kotlin-unit-test-engineer`) | Same as code writer + `bash` (for `./gradlew test`) | Runs test suites |
| Orchestrator (e.g., `pipeline-orchestrator`) | `read_file, write_file, edit, glob, grep_search, bash, agent` | Reads state, dispatches agents |
| Bug Council member | `read_file, glob, grep_search, bash` | Investigation, no file writes |

**Forbidden fields**:

```yaml
# WRONG — never include in Qwen Code subagent frontmatter
model: opus|sonnet|haiku   # NO — Qwen Code picks the model tier
memory: project            # NO — Qwen Code has its own memory system
allowed-tools: ...         # NO — use `tools:` (Qwen Code convention)
```

### Step 4: Write the agent body (Markdown)

The body is the system prompt. Use clear Markdown:

```markdown
---
name: my-new-agent
description: "..."
tools:
  - ...
---

# My New Agent

You are a [role]. Your job is to [purpose].

## When you're invoked

[Trigger conditions — when the orchestrator calls you]

## Process

1. Step one
2. Step two
3. Step three

## Output format

[What you return to the orchestrator]

## Style

[Code style, naming conventions, etc.]

## Skills to consult

- `skills/<skill-name>/` — when to use this skill
```

**For Stage 2 agents**, you MUST also include file partition rules:

```markdown
## File partition (own)

- `src/main/kotlin/**/api/`
- `**/controller/`
- `**/routes/`
- `**/dto/`

**Forbids** (other agents own these):
- `**/domain/`, `**/entity/`, `**/repository/`, `db/migration/`
- `application*.yml`, `logback*.xml`, `gradle.properties`
- `**/client/`, `**/infrastructure/`, `**/event/`, `**/messaging/`
```

### Step 5: Wire the agent into the orchestrator

After creating the file, update the orchestrator that dispatches it:

- **Stage 1 specialists** → update `agents/analytics-orchestrator.md` to add the new agent to its parallel dispatch block
- **Stage 2 specialists** → update `agents/development-orchestrator.md` (especially the partition table)
- **Stage 3 specialists** → update `agents/testing-orchestrator.md`
- **Bug Council member** → update `agents/bug-council-orchestrator.md` (5-member dispatch)
- **New orchestrator** → update `agents/pipeline-orchestrator.md` (stage dispatch loop)

### Step 6: (Optional) Add a SKILL.md mirror

If the agent's behavior is reusable, create a skill at `skills/<derived-skill>/SKILL.md`:

```yaml
---
name: <skill-name>
description: "..."
priority: 5
---
# <Skill Name>
[Mirror the agent's process as a model-invoked skill]
```

### Step 7: Verify

After creating the agent, run the verification suite (use the
`verify-pipeline` skill if available, otherwise):

```bash
# V2: frontmatter validation
python3 -c "
import re, sys
from pathlib import Path
TOOLS_RE = re.compile(r'^tools:\s*(\[[^\]]+\]|\s*$)', re.MULTILINE)
errors = []
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

# V2b: skill references resolve
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

# V3: agent count (should be in 20-30 range)
ACTUAL=$(find agents -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
echo "V3: $ACTUAL agents (expected 20-30)"
```

If all three pass, the agent is correctly added.

### Step 8: Document (optional)

Add a one-line entry to `CHANGELOG.md` under the next version:

```markdown
### Added
- New subagent `<name>` for [purpose]. Stage N parallel dispatch.
```

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| `model: opus` in frontmatter | V2 fails | Remove `model:` field; Qwen Code picks |
| `tools: Read, Edit, Write` (CSV) | V2 fails | Convert to YAML list with snake_case tool names |
| `agents/<category>/<name>.md` (subdir) | Qwen Code doesn't discover | Move to flat `agents/<name>.md` |
| Forgot to update orchestrator | New agent is created but never invoked | Add to orchestrator's parallel dispatch block |
| Stale `skills/kotlin/<name>/` reference | V2b fails | Use `skills/<name>/` (flat, not `kotlin/` subdir) |
| No `description` | Qwen Code won't activate the agent | Add a clear one-line description |
| Tools don't match actual usage | Agent can't perform its job | Match tools to what the agent actually needs |

## Re-enabling a legacy agent (workflow)

To bring back a deprecated agent from v5.0:

```bash
# 1. Find the agent
ls legacy/claude-code/old-agents/<category>/ | grep <keyword>

# 2. Copy to active
cp legacy/claude-code/old-agents/<category>/<name>.md agents/<name>.md

# 3. Strip Claude Code-specific frontmatter
#    Remove: model:, memory:, allowed-tools:
#    Convert: tools: A, B, C → tools: [a, b, c] (YAML list)

# 4. Replace Task({...model:...}) calls with agent({...}) (no model param)

# 5. Update orchestrator that dispatches it

# 6. Run V2 + V2b + V3 verifications
```

## Example: adding a `kotlin-graphql-architect`

**1. Determine role**: Stage 2 specialist, file partition `**/graphql/`

**2. File path**: `agents/kotlin-graphql-architect.md`

**3. Frontmatter**:

```yaml
---
name: kotlin-graphql-architect
description: "Implements GraphQL schemas, resolvers, and data loaders for Kotlin + Spring. Stage 2 parallel agent. Owns **/graphql/ file partition."
tools:
  - read_file
  - edit
  - write_file
  - glob
  - grep_search
  - bash
---
```

**4. Body** (template):

```markdown
# Kotlin GraphQL Architect

You implement GraphQL APIs for Kotlin + Spring projects using
graphql-java or spring-graphql.

## File partition (own)

- `src/main/resources/graphql/**/*.graphqls`
- `src/main/kotlin/**/graphql/`

**Forbids** (other agents own these):
- `**/api/`, `**/controller/`, `**/dto/` (kotlin-api-developer)
- `**/domain/`, `**/entity/`, `**/repository/` (kotlin-data-architect)
- `**/client/`, `**/infrastructure/` (kotlin-integration-specialist)
- `application*.yml`, `**/logback*.xml`, `gradle.properties` (kotlin-config-specialist)

## Skills to consult

- `skills/spring-context-di-reasoning/` — Spring DI
- `skills/kotlin-idiomatic-refactorer-spring-aware/` — Kotlin idioms
- `skills/error-model-validation-architect/` — error handling

## Process

1. Read `analysis.md` for ACs and existing entities
2. Define GraphQL schema (`.graphqls` files)
3. Implement `@Controller`-equivalent resolvers
4. Use DataLoader for N+1 prevention
5. Run `./gradlew ktlintCheck detekt compileKotlin`

## Output

Schema files, resolver classes, data loaders, tests
```

**5. Wire in `agents/development-orchestrator.md`** — add to parallel dispatch:

```markdown
- agent(kotlin-graphql-architect) — owns: **/graphql/
```

**6. Verify**: V2 + V2b + V3 pass.

## Related

- `verify-pipeline` skill — runs the 12-step verification suite
- `CONTRIBUTING.md` — manual contribution guide
- `arch.md` Section 4.4 — subagent architecture
- `agents/pipeline-orchestrator.md` — top-level orchestrator
- `agents/development-orchestrator.md` — Stage 2 partition
- `legacy/claude-code/old-agents/` — deprecated agents available for re-enabling
- `instr.md` Chapter 5 — re-enabling legacy agents
