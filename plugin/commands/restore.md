---
name: restore
description: Restore Claude Code config with the claude-restore CLI
argument-hint: "[dry-run] [home-only] [project-only]"
allowed-tools: Bash(claude-restore:*)
---

You are running the `claude-restore` CLI. Restore is destructive, so behave
conservatively. **Never pass `--force` on your own.**

The user's arguments are: `$ARGUMENTS`

Map each space-separated keyword to a flag (ignore unknown words):

| keyword        | flag             |
|----------------|------------------|
| `dry-run`      | `--dry-run`      |
| `home-only`    | `--home-only`    |
| `project-only` | `--project-only` |

Procedure:

1. First run `claude-restore --dry-run` (plus any home-only/project-only flag)
   to show the restore plan.
2. Show the plan to the user and ask them to confirm in chat.
3. Only after the user explicitly confirms, re-run **with `--force` added** so
   the restore can proceed non-interactively, keeping the pre-restore backup
   enabled (the default).

Examples:

- `/restore` → show the dry-run plan, then on confirmation run `claude-restore --force`
- `/restore dry-run` → just `claude-restore --dry-run` (never escalate)
- `/restore project-only` → `claude-restore --dry-run --project-only`, then on
  confirmation `claude-restore --project-only --force`

Remind the user that some credentials (Keychain, OAuth, env vars) may require
re-authentication after restore.
