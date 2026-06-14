---
description: "Run a Kotlin + Spring code review across the code-archaeologist and the upstream spring-kotlin-code-review skill. No code changes; produces a review report."
argument-hint: [--files <glob>] [--since <ref>]
---

# /devteam:review

Read-only code review for Kotlin + Spring changes. Uses the
upstream `spring-kotlin-code-review` skill and the
`code-archaeologist` agent.

## Usage

```bash
/devteam:review                                # all uncommitted changes
/devteam:review --files "src/main/kotlin/**"  # specific paths
/devteam:review --since main                   # vs branch
```

## Process

1. Detect changes (git diff or glob)
2. Delegate to `spring-kotlin-code-review` (skill in `skills/kotlin/`)
3. Optionally also dispatch `code-archaeologist` to compare with
   existing patterns
4. Aggregate findings into a review report

## Output

```text
CODE REVIEW (Kotlin + Spring)
Files reviewed: 12
Lines: +342 / -127

CRITICAL:
  src/main/kotlin/com/example/UserService.kt:42
    N+1 query in getUserOrders
    Fix: use fetch join or @EntityGraph

HIGH:
  src/main/kotlin/com/example/AuthController.kt:18
    Missing CSRF token validation
    Fix: add .csrf(csrf -> csrf.disable()) only for stateless API

MEDIUM:
  src/main/kotlin/com/example/dto/UserDto.kt:5
    Field name mismatch with API spec
    Fix: rename to match openapi.yml

Summary: 1 critical, 1 high, 1 medium
```

## Skills reference

- `skills/kotlin/spring-kotlin-code-review/` — Spring-specific review
  patterns (DI correctness, transactional boundaries, security)
- `skills/kotlin/kotlin-idiomatic-refactorer-spring-aware/` — Kotlin
  idioms in Spring contexts
- `skills/kotlin/kotlin-spring-proxy-compatibility/` — `@Transactional`
  self-invocation issues, AOP pitfalls
