---
description: Create a new GitHub issue from a description.
argument-hint: "<description>" [--labels <labels>] [--assignee <user>]
---

# /devteam:issue-new

Open a new GitHub issue with structured content.

## Usage

```bash
/devteam:issue-new "OAuth callback returns 500 for expired tokens"
/devteam:issue-new "Add rate limiting to /api/users" --labels enhancement,api
/devteam:issue-new "..." --assignee @me
```

## Process

1. **Parse the description** for:
   - Title (short summary)
   - Type (bug / feature / docs)
   - Repro steps (if bug)
   - Expected vs actual
   - Suggested labels

2. **Fill in template** (auto-detect from description type):

   **Bug**:
   ```markdown
   ## Summary
   <one-line>
   
   ## Reproduction
   1. <step>
   2. <step>
   3. <observed>
   
   ## Expected
   <expected>
   
   ## Environment
   - Version:
   - OS:
   - Browser (if applicable):
   ```

   **Feature**:
   ```markdown
   ## Problem
   <what pain exists>
   
   ## Proposed Solution
   <approach>
   
   ## Alternatives Considered
   <other options>
   
   ## Acceptance Criteria
   - [ ] <criterion>
   ```

3. **Confirm with user** before creating (show the rendered issue).

4. **Create** via GitHub MCP:
   ```
   create_issue(
       owner=..., repo=..., title=...,
       body=..., labels=[...], assignees=[...]
   )
   ```

## Notes

- Requires `GITHUB_TOKEN` and the GitHub MCP server.
- Use `/devteam:issue <N>` afterwards to fix the issue once created.
