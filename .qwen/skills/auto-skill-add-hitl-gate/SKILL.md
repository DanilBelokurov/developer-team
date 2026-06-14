---
name: add-hitl-gate
description: Procedure to add a Human-in-the-Loop (HITL) gate between any two stages of the devteam 3-stage pipeline. Use when you want to pause the pipeline for human review before proceeding to the next stage. Covers state schema, orchestrator prompt changes, dry-run simulation flags, config keys, documentation, and verification.
source: auto-skill
extracted_at: '2026-06-14T15:14:26.109Z'
---

# Add HITL Gate

Procedure to add a Human-in-the-Loop (HITL) gate between any two stages
of the devteam pipeline. A HITL gate pauses pipeline execution and asks
the user (via Qwen Code's `ask_user_question`) for approval before
proceeding to the next stage.

## When to use

Activate this skill when you want to:

- ✅ Add a HITL gate after Stage 2 (Development) — before Stage 3 (Testing)
- ✅ Add a HITL gate after Stage 1 (Analytics) — **already done in v6.1** (use as reference)
- ✅ Add a HITL gate inside a stage (e.g., between sub-agents in Stage 2)
- ✅ Modify the existing HITL gate (e.g., add a 5th option, change the prompt)

**Do NOT use this skill** for:

- ❌ Adding a subagent — see `add-subagent` skill
- ❌ Verifying the pipeline — see `verify-pipeline` skill
- ❌ Debugging a broken HITL gate — manual investigation, check `instr.md` Chapter 10

## Process

### Step 1: Identify the gate location and options

HITL gates in devteam follow a consistent pattern:

| Gate location | When to add |
|---|---|
| `after analytics` (after Stage 1) | Review `analysis.md` before implementing code (default in v6.1) |
| `after development` (after Stage 2) | Review code diff before writing tests |
| `after testing` (after Stage 3) | Approve before PR creation |
| `before pr creation` (within completion) | Approve PR content before GitHub MCP call |

Options presented to the user (default 4):
- `approve` — continue to next stage
- `request_changes` — re-run previous stage
- `edit` — manual edit then continue
- `abort` — halt pipeline

### Step 2: Add state keys (session_state KV, no schema change)

Edit the orchestrator agent (e.g., `agents/pipeline-orchestrator.md`)
to set these KV keys when the gate is paused:

```bash
# When gate is paused:
set_kv_state "stage.<next_stage>.status" "awaiting_approval"
set_kv_state "stage.<next_stage>.hitl_paused_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
set_kv_state "stage.<next_stage>.hitl_action" ""        # empty until user picks
set_kv_state "stage.<next_stage>.analysis_path" "..."    # or "code_diff_path" etc.
set_kv_state "stage.<next_stage>.hitl_resolved_at" ""     # empty until user picks
```

The `hitl_action` is enum: `approve|edit|request_changes|abort`.
For custom actions, add to the list (and update `instr.md` Ch.4).

### Step 3: Add `ask_user_question` invocation in the orchestrator

In the orchestrator's dispatch loop, between stage N and stage N+1:

```python
# After stage N completes, before dispatching stage N+1
if not is_skipped("stage_n+1") and not is_skipped("stage_n"):
    if get_kv_state("stage.stage_n+1.status") != "skipped":
        # Pause for HITL
        set_kv_state("stage.stage_n+1.status", "awaiting_approval")
        set_kv_state("stage.stage_n+1.analysis_path", analysis_output_path)

        action = ask_user_question(
            f"Stage N ({stage_n_name}) complete. Review before Stage N+1?",
            options=[
                {"label": "Approve and continue", "description": "Looks good, proceed."},
                {"label": "Request changes (re-run Stage N)", "description": "..."},
                {"label": "Edit <artifact> manually, then continue", "description": "..."},
                {"label": "Abort pipeline", "description": "Stop here, no further stages."}
            ]
        )

        if action == "Approve and continue":
            set_kv_state("stage.stage_n+1.status", "pending")
            set_kv_state("stage.stage_n+1.hitl_action", "approve")
        elif action == "Request changes (re-run Stage N)":
            set_kv_state("stage.stage_n.status", "pending")  # re-run
            set_kv_state("stage.stage_n+1.hitl_action", "request_changes")
            # Loop back to Stage N
        elif action == "Edit <artifact> manually, then continue":
            set_kv_state("stage.stage_n+1.status", "pending")
            set_kv_state("stage.stage_n+1.hitl_action", "edit")
        elif action == "Abort pipeline":
            set_kv_state("pipeline.active", "false")
            set_kv_state("stage.stage_n+1.hitl_action", "abort")
            emit("PIPELINE ABORTED at HITL gate after Stage N")
            return  # do NOT proceed, do NOT emit EXIT_SIGNAL
```

### Step 4: Add dry-run simulation flags

Edit `scripts/dry-run.sh` to add `--simulate-hitl-<gate>` flags
following the existing pattern:

```bash
# Add new argument parsing
--simulate-hitl-approve-stage2) HITL_ACTION="approve"; GATE="stage2"; shift;;
--simulate-hitl-reject-stage2)  HITL_ACTION="reject";  GATE="stage2"; shift;;
--simulate-hitl-edit-stage2)    HITL_ACTION="edit";    GATE="stage2"; shift;;
--simulate-hitl-abort-stage2)   HITL_ACTION="abort";   GATE="stage2"; shift;;

# In the Stage 2 → Stage 3 transition (or wherever the gate is):
if [ "$GATE" = "stage2" ] && [ "$EFFECTIVE_HITL" = "approve" ]; then
    echo "★ HITL GATE ★ (after Stage 2 Development)"
    echo "  code_diff_path: .devteam/state/agent-runs/diff-<timestamp>.md"
    echo "  ask_user_question:"
    echo "    > Approve and continue to Stage 3"
    echo "    > Request changes (re-run Stage 2)"
    echo "    > Edit code diff manually, then continue"
    echo "    > Abort pipeline"
    # ... handle 4 actions ...
fi
```

### Step 5: Update config.yaml

In `.devteam/config.yaml`, add the gate to the HITL section:

```yaml
pipeline:
  hitl:
    enabled: true
    after_stage: development        # add this
    pause_on: [analytics, development]  # add to list
    resume_actions:
      - approve
      - request_changes
      - edit
      - abort
    headless_fallback: approve
```

### Step 6: Update documentation

Three docs need updates:

1. **`QWEN.md`** — add the new gate to the "State and persistence" section
2. **`instr.md`** Chapter 4 — add the new gate to the "Human-in-the-Loop (HITL) gate" section
3. **`arch.md`** Section 4.5b — add the new gate to the HITL table
4. **`CHANGELOG.md`** — add entry under next version

### Step 7: Verify (use `verify-pipeline` skill)

Run the verification suite. New tests added:

```bash
# V11.X: new gate appears in dry-run
bash scripts/dry-run.sh --feature "X" 2>&1 | grep -q "HITL GATE ★ (after Stage 2)" && echo "OK" || echo "FAIL"

# V11.Y: new simulate flag works
bash scripts/dry-run.sh --feature "X" --simulate-hitl-approve-stage2 2>&1 | grep -q "USER CHOSE Approve" && echo "OK" || echo "FAIL"

# V11.Z: existing gate still works (regression)
bash scripts/dry-run.sh --feature "X" 2>&1 | grep -q "after Stage 1" && echo "OK" || echo "FAIL"
```

Also re-run the full V1-V12 suite to catch any regression.

### Step 8: Migration for existing users

If users have active sessions when the new gate is added, they'll
auto-pause at the new gate on next run (their existing analysis.md
will be evaluated). No migration needed.

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Forget to add new `simulate-hitl-*` flag | V11 fails for new gate | Add flag in dry-run.sh case statement |
| Add gate in wrong location (before stage N completes) | Gate fires too early | Verify stage N's status = "completed" before pause |
| Use `set_kv_state` for `analysis_path` but value is empty | Stage N+1 never starts | Set value before pause; verify with `head -20` |
| Emit `EXIT_SIGNAL: true` after Abort | Stop hook allows exit, but pipeline didn't complete | Remove EXIT_SIGNAL emit on Abort; user re-runs manually |
| Forget to set `hitl_action` to empty before pause | Stale action from previous run | Always set `hitl_action = ""` (or override) at pause |
| Don't handle `request_changes` (re-run loop) | User can't re-run, only abort | Add re-run logic in orchestrator dispatch loop |
| `build.md` doesn't mention new gate | V12 (HITL keywords in prompt) may pass but UX is confusing | Update body to describe the new gate |

## Example: adding a HITL gate after Stage 2 (Development)

**Goal**: After Stage 2 completes (code written, scope check passed,
build verified), pause for human review before Stage 3 (testing).

**1. State keys** (in `agents/pipeline-orchestrator.md`):

```bash
# After Stage 2 completes, before Stage 3
if ! is_skipped "testing" && ! is_skipped "development"; then
    if [ "$(get_kv_state stage.testing.status)" != "skipped" ]; then
        set_kv_state "stage.testing.status" "awaiting_approval"
        set_kv_state "stage.testing.hitl_paused_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        set_kv_state "stage.testing.code_diff_path" ".devteam/state/agent-runs/diff-$(date +%Y%m%d-%H%M%S).md"
        # ... ask_user_question with 4 options ...
    fi
fi
```

**2. ask_user_question** (in same orchestrator):

```python
action = ask_user_question(
    "Stage 2 (Development) complete. Review code diff before Stage 3 (Testing)?",
    options=[
        {"label": "Approve and continue to Stage 3", "description": "Code looks good, write tests."},
        {"label": "Request changes (re-run Stage 2)", "description": "Code needs work; re-run with refined context."},
        {"label": "Edit code manually, then continue", "description": "I'll edit the files; continue after I'm done."},
        {"label": "Abort pipeline", "description": "Stop here, no tests."}
    ]
)
```

**3. Dry-run simulation** (in `scripts/dry-run.sh`):

```bash
# Add new flags
--simulate-hitl-approve-stage2) HITL_ACTION="approve"; HITL_GATE="stage2"; shift;;
--simulate-hitl-reject-stage2)  HITL_ACTION="reject";  HITL_GATE="stage2"; shift;;
--simulate-hitl-edit-stage2)    HITL_ACTION="edit";    HITL_GATE="stage2"; shift;;
--simulate-hitl-abort-stage2)   HITL_ACTION="abort";   HITL_GATE="stage2"; shift;;

# Add Stage 2 → Stage 3 HITL gate output
if [ "$HITL_GATE" = "stage2" ]; then
    echo "★ HITL GATE ★ (after Stage 2 Development)"
    # ... same 4-option print as Stage 1 gate ...
fi
```

**4. Config** (in `.devteam/config.yaml`):

```yaml
pipeline:
  hitl:
    enabled: true
    after_stage: development
    pause_on: [analytics, development]
```

**5. Documentation updates** (see Step 6 above).

**6. Verify**:

```bash
# New gate appears
bash scripts/dry-run.sh --feature "X" 2>&1 | grep -q "after Stage 2"
# Simulate flag works
bash scripts/dry-run.sh --feature "X" --simulate-hitl-approve-stage2 2>&1 | grep -q "USER CHOSE Approve"
# Existing Stage 1 gate still works (no regression)
bash scripts/dry-run.sh --feature "X" 2>&1 | grep -q "after Stage 1"
```

## When NOT to add more gates

HITL is a **round-trip cost**. Each gate adds one user interaction
(typically 1-5 minutes of decision time). For:

- **Trivial features** (single file, <50 lines): HITL is overhead. Skip.
- **High-confidence features** (refactoring, test-only): HITL is friction. Skip.
- **Critical/expensive features** (auth, payment, schema migration):
  HITL is **mandatory**. Always add.

Recommended gate pattern:
- **Mandatory gates**: 1 (after Analytics — when wrong analysis = wasted implementation)
- **Optional gates**: 1 (after Development — when wrong code = wasted tests)
- **Skip**: after Testing (if tests pass, the code is approved)

The default `pipeline.hitl.enabled: true` provides the Analytics gate.
Add Development gate per-project if the team prefers code review before
tests.

## Related

- `add-subagent` skill — adding new specialists
- `verify-pipeline` skill — V1-V12 verification
- `arch.md` Section 4.5b — existing HITL gate reference
- `instr.md` Chapter 4 — HITL gate user docs
- `agents/pipeline-orchestrator.md` — top-level orchestrator
- `scripts/dry-run.sh` — shell mirror with HITL simulation
- `.devteam/config.yaml` `pipeline.hitl` section — gate configuration
- `CHANGELOG.md` v6.1.0 entry — first HITL gate implementation
