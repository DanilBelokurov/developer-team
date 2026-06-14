---
description: Inspect, list, clean, or merge git worktrees used for parallel tracks.
argument-hint: status|list|cleanup|merge [--track <id>]
---

# /devteam:worktree

Manage git worktrees created for parallel execution tracks. Combines
the legacy worktree-status, worktree-list, worktree-cleanup, and
merge-tracks commands.

## Usage

```bash
/devteam:worktree status                  # current state
/devteam:worktree list                    # all worktrees
/devteam:worktree cleanup                 # remove merged worktrees
/devteam:worktree cleanup --track 02      # specific track
/devteam:worktree merge --track 01         # merge a track branch
/devteam:worktree merge --all             # merge all completed tracks
```

## Subcommands

### `status`

Show parallel-track state:

```text
══════════════════════════════════════════
 Worktree Status
══════════════════════════════════════════

Active tracks:
  01  .multi-agent/track-01  (dev-track-01)  ◐  in progress
  02  .multi-agent/track-02  (dev-track-02)  ✓  completed

Branch:  main  @  abc1234
Last sync: 12 minutes ago
══════════════════════════════════════════
```

### `list`

List all worktrees (system + DevTeam):

```text
PATH                              BRANCH             HEAD
.multi-agent/track-01             dev-track-01       a3f9c12
.multi-agent/track-02             dev-track-02       b7e1d44
/Users/me/proj                    main               abc1234
```

### `cleanup`

Remove worktrees whose branches are merged into the base branch.
Branches are kept for history (use `git branch -D <name>` to remove).

```bash
# Remove a specific track
git worktree remove .multi-agent/track-01

# Bulk: remove all merged
git worktree list --porcelain | \
  awk '/^worktree/ {path=$2} /^branch/ {branch=$2} /merged/ {print path}' | \
  xargs -I{} git worktree remove {}
```

### `merge`

Merge a completed track back into the base branch.

```bash
# Single track
git checkout main
git merge dev-track-01 -m "Merge track 01: <name>"

# All completed tracks (sequential, ordered)
git checkout main
for track in dev-track-01 dev-track-02; do
  if git log -1 --pretty=%B $track | grep -q "completed"; then
    git merge $track -m "Merge $track"
  fi
done
```

## Notes

- Worktrees are created automatically by `/devteam:implement` when a
  plan has `parallel_tracks.mode: "worktrees"`. You usually don't
  need to manage them manually.
- The `.multi-agent/` directory is gitignored.
- Branches persist after merge; delete with `git branch -d <name>`
  when you're sure you don't need them.
