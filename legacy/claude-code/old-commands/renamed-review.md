---
description: Run cross-agent code review on recent changes.
argument-hint: [--files <glob>] [--since <ref>] [--type <type>]
---

# /devteam:review

Multi-perspective code review using the orchestrator and language
specialists.

## Usage

```bash
/devteam:review                          # uncommitted changes
/devteam:review --files "src/auth/**"    # specific files
/devteam:review --since main             # vs branch
/devteam:review --type security          # security-focused
```

## Process

1. **Detect changes**:
   - No args: `git diff` (unstaged + staged)
   - `--files`: filter by glob
   - `--since <ref>`: `git diff <ref>...HEAD`
2. **Classify changes**: by file extension and path, identify
   languages, frameworks, layers touched.
3. **Select reviewers**:
   - Always: `code-review-coordinator` (orchestrator)
   - Language-specific: `api-developer-{python,ts,...}` review
     variants
   - Cross-cutting: `security-auditor`, `refactoring-coordinator`
4. **Run reviews in parallel** via the `agent` tool.
5. **Aggregate findings** into a single review report with
   categorized severity (critical / high / medium / low).
6. **For each finding**, propose either:
   - A concrete code fix (delegate to implementation agent), or
   - A follow-up task (create via task loop)

## Output

```text
══════════════════════════════════════════
 DevTeam Review
══════════════════════════════════════════

Reviewed: 7 files, +342/-127 lines

Findings:
  [CRITICAL] src/auth/oauth.py:42
    Missing CSRF token validation in callback handler
    → Security Auditor
    
  [HIGH] src/api/users.py:118
    N+1 query: loop calls `db.get_user(id)` per item
    → Backend Code Reviewer (Python)
    
  [MEDIUM] src/frontend/Dashboard.tsx:67
    useEffect missing dependency `user`
    → Frontend Code Reviewer

Summary: 1 critical, 1 high, 1 medium

Next: /devteam:implement "Address review findings" 
       (will create one fix task per finding)
══════════════════════════════════════════
```

## Notes

- This is a read-only command by default. It produces findings; it
  does NOT auto-fix them.
- Use `/devteam:implement` afterwards to act on the findings.
