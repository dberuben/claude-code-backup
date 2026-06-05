---
name: backup
description: Back up Claude Code config with the claude-backup CLI
argument-hint: "[icloud] [dry-run] [no-project] [no-history] [full] [strict-secrets] [include-env]"
allowed-tools: Bash(claude-backup:*)
---

You are running the `claude-backup` CLI. It is a standalone tool; do not assume
anything about Claude Code's internal state.

The user's arguments are: `$ARGUMENTS`

Map each space-separated keyword to a flag (ignore unknown words):

| keyword          | flag               |
|------------------|--------------------|
| `icloud`         | `--icloud`         |
| `dry-run`        | `--dry-run`        |
| `no-project`     | `--no-project`     |
| `no-history`     | `--no-history`     |
| `full`           | `--full`           |
| `strict-secrets` | `--strict-secrets` |
| `include-env`    | `--include-env`    |

Then run `claude-backup` with the mapped flags via the Bash tool, for example:

- `/backup` → `claude-backup`
- `/backup icloud` → `claude-backup --icloud`
- `/backup dry-run` → `claude-backup --dry-run`
- `/backup icloud strict-secrets` → `claude-backup --icloud --strict-secrets`

Report the resulting archive path and surface any secret warnings the tool
prints. If the `claude-backup` command is not found, tell the user to run the
project's `install.sh` and ensure `~/.local/bin` is on their PATH.
