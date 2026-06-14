---
description: Fetch a GitHub issue and fix it with the standard workflow.
argument-hint: <issue-number>
---

# /devteam:issue

Pull a GitHub issue, optionally interview for context, and fix it.

## Usage

```bash
/devteam:issue 123
/devteam:issue 456 --council
```

## Process

### Phase 1: Fetch Issue

Use the GitHub MCP server:

```
get_issue(owner=<repo-owner>, repo=<repo-name>, issue_number=N)
```

Extract: title, body, labels, assignees, comments, linked PRs.

### Phase 2: Triage

- Determine severity from labels (`bug`, `critical`, `security`)
- Check linked PRs: is someone already working on it?
- Read related issues for context

### Phase 3: Interview (if ambiguous)

If the issue lacks reproduction steps, expected behavior, or
acceptance criteria, ask the user for clarification. Otherwise
proceed.

### Phase 4: Execute

Treat the issue as a single ad-hoc task and run `/devteam:implement`
with the synthesized description.

Use `--council` if the issue is labeled `bug` + `critical`/`security`.

### Phase 5: PR Creation

After the fix passes quality gates:

```
create_pull_request(
    owner=<owner>,
    repo=<repo>,
    title="Fix #<N>: <short title>",
    body="Closes #<N>\n\n## Summary\n<...>\n\n## Test plan\n<...>",
    base="main",
    head="devteam/issue-<N>"
)
```

### Phase 6: Complete

```text
ISSUE FIXED

Issue: #<N> — <title>
PR: <url>
EXIT_SIGNAL: true
```

## Notes

- Requires `GITHUB_TOKEN` env var and the GitHub MCP server to be
  configured (handled automatically by `qwen-extension.json`).
- If the issue references external context (docs, designs), fetch
  those first before delegating.
