---
description: Detect design system drift across components.
argument-hint: [--severity <level>] [--fix]
---

# /devteam:design-drift

Deep audit of design system consistency.

## Usage

```bash
/devteam:design-drift              # full report
/devteam:design-drift --fix        # propose fixes
/devteam:design-drift --severity high
```

## Checks

| Category | What it checks |
|---|---|
| Colors | Hardcoded hex/rgb outside token files; mismatched palettes |
| Typography | Font-family, size, weight not matching scale |
| Spacing | Margin/padding values not in spacing scale |
| Radii | Border-radius values not from token set |
| Shadows | Hardcoded box-shadow vs shadow tokens |
| Accessibility | Contrast ratios for text/background pairs |
| Naming | Component prop names inconsistent (e.g. `size=sm` vs `size=small`) |

## Process

1. Build a fingerprint of the design system from `src/theme/`.
2. Walk all components in `src/components/`.
3. For each style value, check if it matches a token (or a multiple
   of a base unit for spacing).
4. Classify violations:
   - **critical**: accessibility failures
   - **high**: tokens bypassed for major surfaces
   - **medium**: minor inconsistencies
   - **low**: stylistic preferences
5. If `--fix`, generate proposed patches (do NOT apply unless user
   runs `/devteam:implement` to act on them).

## Output

```text
══════════════════════════════════════════
 Design Drift Report
══════════════════════════════════════════

Files scanned: 47
Violations:     23 (2 critical, 5 high, 11 medium, 5 low)

CRITICAL:
  src/components/Modal.tsx:18
    Backdrop color hardcoded: rgba(0,0,0,0.5)
    Should use: var(--color-backdrop) or theme.backdrop

  src/components/Toast.tsx:24
    Text contrast 3.2:1 on bg-warning
    Required: 4.5:1 (WCAG AA)

HIGH:
  src/components/Button.tsx:42
    Color #3366ff not in palette (closest: primary-500 #3b82f6)

[...truncated...]

Use /devteam:implement "Fix design drift findings" to act on these.
══════════════════════════════════════════
```
