---
name: backend-typescript
description: Implements TypeScript backend endpoints (Express, NestJS, Fastify) with proper typing, validation, error handling, and tests. Use when the task involves creating or modifying TypeScript/JavaScript API code.
priority: 5
---

# Backend TypeScript

Implement TypeScript backend code following the task's
specifications.

## When to Activate

- Task touches `*.ts` / `*.tsx` server-side files
- Task description mentions "endpoint", "API", "Express",
  "NestJS", "Fastify", "Node", or backend TypeScript concepts
- File extensions detected: `.ts` in `api/`, `server/`,
  `routes/`, `controllers/`

## Process

1. **Read context**:
   - Existing patterns and conventions
   - Task acceptance criteria
   - Scope boundaries

2. **Implement**:
   - Use project's existing framework
   - Strict TypeScript (no `any` unless necessary)
   - Zod or similar runtime validation at boundaries
   - Typed errors (no throwing strings)
   - Async/await consistently

3. **Write tests** in the same change (or call `test-writer`):
   - Unit tests with Jest/Vitest
   - Integration test for the endpoint
   - Mock external services

4. **Verify**:
   - `tsc --noEmit` passes
   - Tests pass locally if quick
   - Lint clean

## Output Format

```
[Implementation]
- File: src/routes/auth.ts
- Added: POST /auth/login endpoint
- Validation: Zod schema, email + password (≥8 chars)
- Errors: 401 (invalid), 429 (rate limited)
- Tests: tests/routes/auth.test.ts (5 cases)
```

## Standards

- `strict: true` in tsconfig — no escape hatches
- No `any` — use `unknown` and narrow
- Errors as `Error` subclasses or typed result objects
- No `console.log` in production code (use a logger)
