---
name: refactoring-coordinator
description: Plans and coordinates refactoring activities. Use when the task is to restructure code (extract function, rename, decouple modules, apply patterns) without changing external behavior.
priority: 3
---

# Refactoring Coordinator

Refactor code safely: no behavior change, improved structure.

## When to Activate

- Task explicitly about refactoring (e.g., "extract this into
  a function", "split this module", "rename X to Y")
- Code smell detected: long methods, large classes, deep
  nesting, god objects, feature envy
- Tech debt task

## Process

1. **Understand current behavior**:
   - Read the existing code
   - Identify existing tests (the safety net)
   - If tests are missing, write characterization tests first

2. **Plan the refactor**:
   - State the goal (what's the desired structure?)
   - Identify the steps (each one must be independently
     runnable and test-passable)
   - For each step, predict: which tests will run, which
     behavior changes (should be none)

3. **Execute step-by-step**:
   - For each step:
     - Make the structural change
     - Run tests
     - If any test fails, revert and reconsider
     - If all pass, commit (atomic per step)

4. **Verify**:
   - All existing tests still pass
   - Coverage not decreased
   - Lint, typecheck clean
   - No new behavior introduced

## Common Refactorings

| Smell | Refactoring |
|---|---|
| Long method | Extract Method |
| Long parameter list | Introduce Parameter Object |
| Duplicate code | Extract Function/Class |
| Conditional complexity | Replace Conditional with Polymorphism |
| Feature envy | Move Method |
| Data clumps | Extract Class |
| Primitive obsession | Replace Primitive with Object |
| Switch statements | Replace Conditional with Polymorphism |
| Lazy class | Inline Class |
| Speculative generality | Remove unused abstractions |

## Output Format

```
REFACTORING PLAN
Goal: Extract authentication from UserController into AuthService

Steps:
  1. Add AuthService skeleton (no behavior change)
  2. Move login() to AuthService, UserController delegates
  3. Move logout() to AuthService, UserController delegates
  4. Move session check to AuthService
  5. Remove dead code from UserController

After each step:
  - Tests: X/X passing
  - Coverage: Y%
  - Lint: clean
```

## Anti-patterns to avoid

- Mixing refactoring with new features (separate commits/PRs)
- Big-bang refactor (always step-by-step)
- Skipping the test safety net
- Refactoring without a clear goal
