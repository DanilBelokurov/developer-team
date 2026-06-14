---
name: bug-council
description: Convene a 5-agent diagnostic council for complex bugs. Use when a critical bug resists diagnosis, 3+ fix attempts have failed, or a bug has architectural implications. Members: root-cause-analyst, code-archaeologist, pattern-matcher, systems-thinker, adversarial-tester.
priority: 10
---

# Bug Council

Multi-perspective bug diagnosis. Five specialized agents analyze the
same problem in parallel, then their findings are synthesized into
a unified diagnosis and fix plan.

## Activation Triggers

- Bug severity: critical or high
- 3+ failed fix attempts at the top model tier
- Complexity score ≥ 10
- Explicit `bug_council: true` flag

## Council Members

| Member | Focus |
|---|---|
| `root-cause-analyst` | Error analysis, hypothesis generation, causal chains |
| `code-archaeologist` | Git history, regression detection, blame analysis |
| `pattern-matcher` | Similar bugs, anti-patterns, codebase search |
| `systems-thinker` | Dependencies, architectural issues, integration points |
| `adversarial-tester` | Edge cases, security vectors, attack scenarios |

## Process

1. **Frame the bug**: collect error message, stack trace, repro
   steps, recent changes, environment.
2. **Dispatch in parallel**: spawn all 5 council members
   concurrently via the `agent` tool. Each gets the same context
   but a different perspective.
3. **Collect findings**: each member returns a structured report:
   ```
   ## Council Member Report — <name>
   Diagnosis: <hypothesis>
   Evidence:  <file:line, log, history>
   Fix:       <concrete change>
   Confidence: <low|medium|high>
   ```
4. **Synthesize**: identify consensus diagnoses, complementary
   findings, and conflicting hypotheses.
5. **Propose unified fix**: one concrete plan that addresses the
   agreed root cause.
6. **Implement**: delegate to the appropriate specialist
   (e.g., `api-developer-python`).
7. **Verify**: regression test + full quality gates.

## Anti-abandonment

The council exists precisely because single-perspective diagnosis
often fails on hard bugs. Do not skip the council for "obviously
simple" bugs that have already failed once.
