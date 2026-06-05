---
name: backup-doctor
description: Diagnose the claude-code-backup environment
allowed-tools: Bash(claude-backup:*)
---

Run the claude-code-backup self-diagnostics:

!`claude-backup doctor`

Interpret the output for the user. Call out any ✗ failures first (these block
backup/restore), then any ⚠ warnings (e.g. missing PATH entry, possible secrets
in config, no iCloud directory). Suggest concrete fixes. If `claude-backup` is
not found, tell the user to run the project's `install.sh`.
