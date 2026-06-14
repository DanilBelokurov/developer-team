---
name: backend-python
description: Implements Python backend endpoints (FastAPI, Django, Flask) with proper validation, error handling, and tests. Use when the task involves creating or modifying Python API code, models, or services.
priority: 5
---

# Backend Python

Implement Python backend code following the task's specifications.

## When to Activate

- Task touches `*.py` files in API/service layers
- Task description mentions "endpoint", "API", "Django",
  "FastAPI", "Flask", or backend concepts
- File extensions detected: `.py` in `api/`, `services/`, `views/`

## Process

1. **Read context**:
   - Existing patterns (read related files first)
   - Task acceptance criteria
   - Scope boundaries

2. **Implement**:
   - Use the project's existing framework (don't introduce
     new dependencies without approval)
   - Add input validation at the boundary
   - Handle errors explicitly (no bare `except`)
   - Add type hints
   - Follow PEP 8 and the project's style

3. **Write tests** in the same change (or call `test-writer`
   skill if scope allows):
   - Unit tests for new functions
   - Integration test for the endpoint

4. **Verify**:
   - Run the project's test command locally if quick
   - Document any manual verification steps

## Output Format

```
[Implementation]
- File: src/api/auth/login.py
- Added: POST /auth/login endpoint with email+password
- Validation: email format, password ≥8 chars
- Errors: 401 (invalid creds), 429 (rate limited)
- Tests: tests/api/auth/test_login.py (4 cases)
```

## Standards

- All public functions have type hints
- All endpoints have OpenAPI docstrings
- No SQL string interpolation (use parameterized queries)
- No secrets in code (use env vars)
