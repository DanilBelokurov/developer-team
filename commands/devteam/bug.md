---
description: Diagnose and fix a bug, optionally activating the Bug Council.
argument-hint: "<description>" [--council] [--severity critical|high|medium|low] [--eco]
---

# /devteam:bug

Diagnostic workflow with optional 5-agent Bug Council for complex issues.

## Usage

```bash
/devteam:bug "Login fails for guest users"
/devteam:bug "Memory leak in image processor" --council
/devteam:bug "Race condition in checkout" --severity critical
/devteam:bug "Minor CSS issue" --eco
```

## Process

### Phase 1: Triage

- Parse description for severity hints (`critical`, `broken`, `crash` → high).
- If `--severity` provided, use it directly.
- If ambiguous, ask the user: severity + reproduction steps.

### Phase 2: Initial Diagnosis

Delegate to `root-cause-analyst` (the primary Bug Council member):

```python
agent(
    subagent_type="root-cause-analyst",
    prompt="Bug: <description>\nSeverity: <level>\nReproduction: <steps>"
)
```

Read recent error logs, stack traces, and relevant code paths. Produce
a hypothesis tree.

### Phase 3: Bug Council Activation

Activate the 5-agent council if ANY of:
- `--council` flag present
- Severity is `critical` or `high`
- 3+ failed opus attempts during fix
- Complexity score ≥ 10

Council members (run in parallel via the `agent` tool):

| Agent | Focus |
|---|---|
| `root-cause-analyst` | Error analysis, hypothesis generation, causal chains |
| `code-archaeologist` | Git history, regression detection, blame |
| `pattern-matcher` | Similar bugs, anti-pattern identification |
| `systems-thinker` | Dependencies, architectural issues |
| `adversarial-tester` | Edge cases, security vectors, attack vectors |

Delegate to `bug-council-orchestrator` to coordinate:

```python
agent(
    subagent_type="bug-council-orchestrator",
    prompt="Convene Bug Council for: <description>. Failure history: <...>"
)
```

### Phase 4: Synthesized Fix

After council reports, synthesize a unified diagnosis and fix plan.
Delegate implementation to the appropriate specialist (e.g.,
`api-developer-python`).

### Phase 5: Verify

- Add regression test that fails on the original bug and passes on the fix.
- Run full quality gate suite.
- Confirm scope: only the necessary files were modified.

### Phase 6: Complete

```text
BUG FIXED

Bug: <description>
Root cause: <one-line>
Files changed: <list>
Regression test: <path>:<line>
Bug Council: <yes/no>

EXIT_SIGNAL: true
```

## Anti-abandonment

If a fix attempt seems to fail repeatedly, the persistence hook will
block session exit. Do NOT respond with phrases like:
- "I cannot fix this"
- "You should try manually"
- "This requires human intervention"

Instead, re-engage: try a different approach, escalate model, or
activate Bug Council.
