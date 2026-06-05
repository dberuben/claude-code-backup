---
name: backup-status
description: Show backup status and the claude-code-backup banner
allowed-tools: Bash(claude-backup:*), Bash(claude-backup-banner:*)
---

Show the current backup status.

Existing backups:

!`claude-backup list`

Status banner:

!`claude-backup-banner`

Summarize for the user: how many backups exist, the age of the most recent one,
and whether the banner flags a missing/stale backup or a possible secret in the
config. If the commands are not found, point the user at `install.sh`.
