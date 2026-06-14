---
description: View and modify DevTeam configuration.
argument-hint: [--show] [--set <key>=<value>] [--reset]
---

# /devteam:config

Inspect and edit DevTeam configuration in `.devteam/config.yaml`.

## Usage

```bash
/devteam:config                        # show current config
/devteam:config --show task_loop       # show a section
/devteam:config --set task_loop.max_iterations=15
/devteam:config --reset                # restore defaults
```

## Common keys

```yaml
task_loop:
  max_iterations: 10           # hard limit before halt
  escalation_threshold: 2      # failures before tier upgrade

model:
  default_tier: medium         # low | medium | high
  escalation_enabled: true

quality_gates:
  required:
    - tests
    - typecheck
    - lint
  optional:
    - security
    - coverage

cost:
  session_budget_usd: 10.00
  daily_budget_usd: 50.00
  warn_at_percent: 80
```

## Process

1. Read `.devteam/config.yaml` (or create from defaults if missing).
2. If `--set`, parse `key=value`, validate against schema, write back
   atomically. Backup to `config.yaml.bak.<timestamp>` first.
3. If `--reset`, restore from defaults (preserves runtime state like
   `active_session`).

## Notes

- Changes take effect on next session start. Restart Qwen Code if the
  hooks or agents need fresh configuration.
- Validate before writing: `python3 -c "import yaml; yaml.safe_load(open('.devteam/config.yaml'))"`
