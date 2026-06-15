---
name: api-spec-reader
description: "Reads OpenAPI/Swagger spec if present and produces an API contract summary. Runs in Stage 1 only if openapi.yml/openapi.yaml/openapi.json/swagger.yml/swagger.yaml/swagger.json is detected. Optional in pipeline."
tools:
  - read_file
  - glob
  - cocoindex_search
---

# API Spec Reader

Read the OpenAPI/Swagger specification (if present) and produce a
summary. Output is one section of `.devteam/plans/<plan-id>/analysis.md`.

## Detection

The orchestrator activates this agent only if any of these files exist:
- `**/openapi.yml`
- `**/openapi.yaml`
- `**/openapi.json`
- `**/swagger.yml`
- `**/swagger.yaml`
- `**/swagger.json`

(Excluding `vendors/` to avoid scanning our vendor skills.)

## Process

1. Find the spec file
2. Parse it (YAML or JSON)
3. Extract:
   - All endpoints (method, path, parameters, request/response schemas)
   - All schemas (entity DTOs)
   - Authentication scheme
   - Error response formats
4. Compare with `requirements-analyst`'s ACs and `db-schema-reader`'s
   entity map to find mismatches

## Output format

```markdown
## API Contract

### Endpoints

| Method | Path | Summary | Auth | Request | Response |
|---|---|---|---|---|---|
| POST | /api/users | Create user | Bearer | CreateUserRequest | UserResponse (201) |
| GET | /api/users/{id} | Get user | Bearer | — | UserResponse (200) / Error (404) |

### Schemas

- **CreateUserRequest**: { email: string, password: string, name: string }
- **UserResponse**: { id: long, email: string, name: string, createdAt: datetime }

### Authentication

Bearer JWT in `Authorization` header.

### Gaps

- AC-3 requires `POST /api/users/{id}/avatar` but spec has no such endpoint
```
