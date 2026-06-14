---
description: Generate or validate the design system for a frontend project.
argument-hint: [--generate] [--validate] [--target <path>]
---

# /devteam:design

Design system generation and validation.

## Usage

```bash
/devteam:design --generate           # create new design tokens
/devteam:design --validate           # check existing tokens
/devteam:design --target src/theme   # specific path
```

## Process

### `--generate`

1. Detect framework: React, Vue, Svelte, Angular, plain CSS.
2. Read `package.json` for UI library (MUI, Chakra, Tailwind, shadcn).
3. Produce a starter design system:
   - `src/theme/tokens.css` — colors, spacing, typography, radii
   - `src/theme/components.css` — base component styles
   - `src/theme/README.md` — usage guide
4. Validate accessibility: WCAG 2.1 AA contrast ratios.
5. Commit the design system as a single commit.

### `--validate`

1. Read existing tokens and component CSS.
2. Check consistency:
   - All colors from token palette (no hardcoded hex)
   - Spacing follows scale (4px, 8px, 16px, 24px, 32px, …)
   - Typography uses defined scale
3. Run WCAG contrast checks.
4. Report violations with fix suggestions.

## Output

```text
══════════════════════════════════════════
 Design System Validation
══════════════════════════════════════════

Tokens found: 24 colors, 6 spacing, 5 typography
Components:   18 styled components

✓ All colors from palette
✓ Spacing follows scale
✗ Hardcoded color: src/components/Button.tsx:42 (#3366ff)
✗ WCAG fail:   text-muted on bg-subtle (3.1:1, need 4.5:1)

2 violations — see design-drift for full report.
══════════════════════════════════════════
```

See `/devteam:design-drift` for a deeper audit.
