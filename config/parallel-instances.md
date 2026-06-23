# Parallel Instance & Plan Execution

This document covers:
1. What happens when `/devteam:implement` runs with multiple plans
2. Running multiple instances simultaneously
3. Git repository requirements
4. Git worktree integration for parallel plan development

## Question 1: `/devteam:implement` with Multiple Plans

### Current Behavior

When `/devteam:implement` is run and multiple plans exist:

```
/devteam:implement

# If no active plan selected:
⚠️  Multiple plans available. Please select one:

┌──────────────────────────────────────────────────────────────┐
│ #  │ Name                 │ Type    │ Status      │ Progress │
├──────────────────────────────────────────────────────────────┤
│ 1  │ Task Manager App     │ project │ ✅ complete │ 5/5      │
│ 2  │ Push Notifications   │ feature │ 🔄 active   │ 1/2      │
│ 3  │ Dark Mode Support    │ feature │ 📋 planned  │ 0/1      │
└──────────────────────────────────────────────────────────────┘

Select a plan to execute (enter number): _

Or use: /devteam:implement --plan <name>
```

### Smart Auto-Selection

If only ONE plan is `in_progress` or `planned`:
```
/devteam:implement

# Auto-selects the only actionable plan
✅ Auto-selected: Dark Mode Support (only pending plan)

Starting autonomous execution...
```

### Explicit Selection

Always works:
```
/devteam:implement --plan dark-mode
/devteam:implement --plan 3
```

## Question 2: Two Instances, Two Plans

### The Problem

If User A runs `/devteam:implement` on Plan A while User B runs `/devteam:implement` on Plan B:
- Both might modify the same files
- Git conflicts will occur
- State files can get corrupted
- Chaos ensues

### Solution: Plan Locking + Git Worktrees

#### Plan Lock Files

When a plan starts execution, it acquires a lock:

```
.devteam/plans/feature-dark-mode/
├── lock.json          ← Lock file
├── devteam.db         ← SQLite state database
├── tasks/
└── sprints/
```

**Lock file format:**
```json
{
  "locked_by": "qwen-instance-abc123",
  "locked_at": "2025-01-29T10:00:00Z",
  "pid": 12345,
  "hostname": "users-laptop",
  "plan_id": "feature-dark-mode",
  "expires_at": "2025-01-29T12:00:00Z"
}
```

#### Lock Acquisition Process

```
/devteam:implement --plan dark-mode

Step 1: Check for existing lock
        → If lock.json exists AND not expired AND process alive:
          ❌ "Plan is locked by another instance"
        → If lock.json exists AND expired:
          ⚠️  "Stale lock detected, claiming..."
        → If no lock:
          ✅ Create lock.json

Step 2: If lock acquired, proceed with execution
Step 3: On exit (normal or crash), release lock
```

#### Second Instance Behavior

```
# Instance 1 is running dark-mode plan
# Instance 2 tries to run the same plan:

/devteam:implement --plan dark-mode

🔒 Plan "dark-mode" is locked

Currently being executed by another instance:
  Started: 10 minutes ago
  Instance: qwen-instance-abc123

Options:
  1. Wait for lock release (recommended)
  2. Execute a DIFFERENT plan
  3. Force unlock (DANGER - may corrupt state)

To execute a different plan:
  /devteam:implement --plan notifications

To force (not recommended):
  /devteam:implement --plan dark-mode --force-unlock
```

#### Parallel Plans with Git Worktrees

For TRUE parallel execution (two plans at the same time), we use git worktrees:

```
project/                           ← Main repository
├── .devteam/
│   └── plans/
│       ├── feature-dark-mode/
│       └── feature-notifications/
│
└── .devteam-worktrees/            ← Auto-created for parallel plans
    ├── feature-dark-mode/         ← Worktree for dark mode
    │   └── (full project copy)
    └── feature-notifications/     ← Worktree for notifications
        └── (full project copy)
```

## Question 3: Git Repository Requirements

### Git is REQUIRED

DevTeam requires a git repository for:
1. **Change tracking** - Know what was modified
2. **Rollback capability** - Undo broken changes
3. **Worktrees** - Parallel plan execution
4. **Merge management** - Combine feature work

### Auto-Initialization

When `/devteam:plan` runs:

```
/devteam:plan "Build a task manager"

Step 1: Check for git repository
        → git rev-parse --git-dir

If NOT a git repo:
┌──────────────────────────────────────────────────────────────┐
│  📁 No Git Repository Detected                               │
│                                                              │
│  DevTeam requires a git repository for:                      │
│  • Change tracking and rollback                              │
│  • Parallel plan execution (worktrees)                       │
│  • Safe merge of feature branches                            │
│                                                              │
│  Initialize a git repository now? (yes/no)                   │
└──────────────────────────────────────────────────────────────┘

If user says yes:
  → git init
  → git add .
  → git commit -m "Initial commit before DevTeam planning"
  → ✅ Git repository initialized

If user says no:
  → ❌ Cannot proceed without git repository
```

### Pre-Planning Git Setup

```yaml
# Automatic git setup during /devteam:plan
git_setup:
  check: "git rev-parse --git-dir"

  if_not_repo:
    prompt_user: true
    auto_init_if_confirmed: true
    initial_commit_message: "Initial commit before DevTeam planning"

  if_repo:
    check_clean: true
    if_dirty:
      prompt: "You have uncommitted changes. Commit before planning? (yes/no)"
      if_yes: auto_commit
      commit_message: "Pre-planning snapshot"
```

## Question 4: Git Worktrees for Parallel Development

### When Worktrees Are Used

```yaml
worktree_triggers:
  # Automatically create worktree when:
  automatic:
    - second_concurrent_plan: true     # When 2nd plan starts while 1st running
    - explicit_parallel: true          # --parallel flag

  # User can request worktree:
  manual:
    - "/devteam:plan --worktree"
    - "/devteam:implement --worktree"
```

### Behind-the-Scenes Workflow

**User Experience (simple):**
```bash
# Terminal 1
/devteam:plan --feature "Add dark mode"
/devteam:implement

# Terminal 2 (while Terminal 1 still running)
/devteam:plan --feature "Add notifications"
/devteam:implement
```

**What happens automatically:**

```
Terminal 2 runs /devteam:implement

System detects:
  → Plan "dark-mode" is currently executing in another instance
  → Plan "notifications" needs to run in parallel

Auto-worktree creation:
┌──────────────────────────────────────────────────────────────┐
│  🔀 Parallel Execution Detected                              │
│                                                              │
│  Another plan is currently running:                          │
│    Plan: dark-mode (1/2 sprints complete)                    │
│    Instance: Terminal 1                                      │
│                                                              │
│  Creating isolated workspace for "notifications"...          │
│                                                              │
│  ✅ Worktree created: .devteam-worktrees/feature-notifications/
│                                                              │
│  Your changes will be isolated until merge.                  │
│  Starting execution in worktree...                           │
└──────────────────────────────────────────────────────────────┘
```

**Git Commands (hidden from user):**
```bash
# System automatically runs:
git worktree add .devteam-worktrees/feature-notifications -b devteam/feature-notifications

# Changes directory to worktree
cd .devteam-worktrees/feature-notifications

# Execute plan in isolated environment
# All changes happen here, not in main repo
```

### Transparent Merge on Completion

When a worktree plan completes:

```
╔══════════════════════════════════════════════════════════════╗
║  🎉 PLAN COMPLETE: Push Notifications                        ║
╚══════════════════════════════════════════════════════════════╝

This plan was executed in an isolated worktree.

Changes ready to merge:
  • 12 files modified
  • 3 files added
  • Branch: devteam/feature-notifications

Merge options:
  1. Merge now (recommended if no conflicts expected)
  2. Create pull request (for review)
  3. Keep worktree (merge later manually)

Select option (1/2/3): _
```

**Option 1: Auto-merge**
```
Merging devteam/feature-notifications into main...

Checking for conflicts...
  ✅ No conflicts detected

Performing merge...
  ✅ Merge successful

Cleaning up worktree...
  ✅ Worktree removed

All changes are now in your main branch.
```

**Option 2: Pull Request**
```
Creating pull request...

  → git push origin devteam/feature-notifications
  → gh pr create --title "Feature: Push Notifications" ...

✅ Pull request created: #42

Worktree kept for potential updates.
To clean up later: /devteam:worktree cleanup
```

### Conflict Handling

If conflicts occur during merge:

```
⚠️  Merge Conflicts Detected

The following files have conflicts:
  • src/components/Header.tsx (modified in both plans)
  • src/styles/theme.ts (modified in both plans)

Options:
  1. Resolve conflicts interactively
  2. Keep both versions (create PR for manual review)
  3. Abort merge (keep worktree)

Select option (1/2/3): _
```

### Worktree State Tracking

```yaml
# .devteam/worktrees.yaml (auto-managed)
worktrees:
  feature-notifications:
    path: ".devteam-worktrees/feature-notifications"
    branch: "devteam/feature-notifications"
    plan_id: "feature-notifications"
    created_at: "2025-01-29T10:00:00Z"
    status: active

  feature-dark-mode:
    path: ".devteam-worktrees/feature-dark-mode"
    branch: "devteam/feature-dark-mode"
    plan_id: "feature-dark-mode"
    created_at: "2025-01-29T09:30:00Z"
    status: completed
    merged: true
    merged_at: "2025-01-29T11:00:00Z"
```

## Complete Flow: Two Instances, Two Plans

```
┌─────────────────────────────────────────────────────────────────┐
│  PARALLEL PLAN EXECUTION FLOW                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Instance 1                        Instance 2                    │
│  ──────────                        ──────────                    │
│                                                                  │
│  /devteam:plan --feature           /devteam:plan --feature       │
│  "dark mode"                       "notifications"               │
│       │                                  │                       │
│       ▼                                  ▼                       │
│  Creates plan in                   Creates plan in               │
│  .devteam/plans/dark-mode/         .devteam/plans/notifications/ │
│       │                                  │                       │
│       ▼                                  ▼                       │
│  /devteam:implement                     /devteam:implement                 │
│       │                                  │                       │
│       ▼                                  ▼                       │
│  Acquires lock                     Detects lock on dark-mode     │
│  lock.json created                 Own plan not locked           │
│       │                                  │                       │
│       ▼                                  ▼                       │
│  Executes in main repo             Detects parallel execution    │
│  (first plan)                      Creates worktree automatically│
│       │                                  │                       │
│       │                            cd .devteam-worktrees/notif/  │
│       │                                  │                       │
│       ▼                                  ▼                       │
│  Working on dark mode...           Working on notifications...   │
│       │                                  │                       │
│       ▼                                  ▼                       │
│  Plan complete                     Plan complete                 │
│  Release lock                      Prompt to merge               │
│       │                                  │                       │
│       │                            User selects: Merge now       │
│       │                                  │                       │
│       │                            Auto-merge to main            │
│       │                            Cleanup worktree              │
│       │                                  │                       │
│       ▼                                  ▼                       │
│  Main repo has                     Main repo has both features   │
│  dark mode feature                 merged cleanly                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Configuration

```yaml
# .devteam/config.yaml
parallel_execution:
  enabled: true

  # Lock settings
  locks:
    enabled: true
    timeout_hours: 2           # Lock expires after 2 hours
    stale_threshold_minutes: 30  # Consider stale if no heartbeat
    heartbeat_interval_seconds: 60

  # Worktree settings
  worktrees:
    auto_create: true          # Automatically create for parallel plans
    base_path: ".devteam-worktrees"
    auto_cleanup: true         # Remove after merge

  # Merge settings
  merge:
    auto_merge_if_clean: false  # Prompt user even if no conflicts
    create_backup_branch: true  # Backup before merge

git:
  required: true
  auto_init: prompt            # Ask user before initializing
  pre_plan_commit: prompt      # Ask to commit dirty changes
```

## User Commands

```bash
# List worktrees
/devteam:worktree list

# Status of all worktrees
/devteam:worktree status

# Clean up merged worktrees
/devteam:worktree cleanup

# Force cleanup (removes all worktrees)
/devteam:worktree cleanup --all

# Manually merge a worktree
/devteam:worktree merge notifications
```

## Summary

| Scenario | Behavior |
|----------|----------|
| `/devteam:implement` with no plan selected | Prompts user to select |
| `/devteam:implement` with one actionable plan | Auto-selects it |
| Two instances, same plan | Second instance blocked (locked) |
| Two instances, different plans | Auto-creates worktree for isolation |
| No git repo | Prompts to initialize |
| Git dirty | Prompts to commit before planning |
| Plan complete in worktree | Prompts to merge/PR/keep |
| Merge conflicts | Interactive resolution or PR for review |

**Key Principle:** The user never needs to understand git worktrees. It all happens automatically, and they just see their isolated work merged when ready.
