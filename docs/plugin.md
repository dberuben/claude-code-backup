# Claude Code plugin

The plugin is a **thin convenience layer** over the CLI. Every slash command
shells out to `claude-backup` / `claude-restore` / `claude-backup-banner`. If
the plugin is unavailable, the CLI still does everything; the plugin adds
nothing that the commands above cannot do directly.

> **Format note.** This plugin follows the current official Claude Code layout,
> where the manifest lives at **`.claude-plugin/plugin.json`** (not
> `plugin/plugin.json` as in some older examples). Slash commands are plain
> Markdown files under `commands/`. We keep the plugin in a top-level `plugin/`
> directory and distribute it via a repo-root `.claude-plugin/marketplace.json`.
> If the format changes again, only these files need updating — the CLI is
> unaffected.

## Layout

```
plugin/
├── .claude-plugin/
│   └── plugin.json          # manifest (name, version, description, …)
└── commands/
    ├── backup.md            # /backup
    ├── restore.md           # /restore
    ├── backup-status.md     # /backup-status
    └── backup-doctor.md     # /backup-doctor

.claude-plugin/
└── marketplace.json         # repo-root marketplace for distribution
```

## Installing the plugin

**Local development (session-scoped):**

```bash
claude --plugin-dir /path/to/claude-code-backup/plugin
# then, after edits:
/reload-plugins
```

**Via a marketplace (for sharing):**

```bash
/plugin marketplace add https://github.com/dberuben/claude-code-backup
/plugin install claude-code-backup@claude-code-backup
```

The plugin assumes `claude-backup`, `claude-restore` and `claude-backup-banner`
are on your `PATH` (run `install.sh` first). If they are not found, the commands
tell you to run `install.sh`.

## Commands

### `/backup [dry-run] [no-project] [no-history] [full] [strict-secrets] [include-env]`

Maps keywords to CLI flags and runs `claude-backup`:

| keyword | flag |
|---------|------|
| `dry-run` | `--dry-run` |
| `no-project` | `--no-project` |
| `no-history` | `--no-history` |
| `full` | `--full` |
| `strict-secrets` | `--strict-secrets` |
| `include-env` | `--include-env` |

Examples: `/backup`, `/backup dry-run`, `/backup no-history`,
`/backup dry-run strict-secrets`.

### `/restore [dry-run] [home-only] [project-only]`

Maps `dry-run` → `--dry-run`, `home-only` → `--home-only`,
`project-only` → `--project-only`.

For safety the command **never passes `--force` on its own**: it first runs a
dry-run to show the plan, asks you to confirm in chat, and only then re-runs
with `--force`. Examples: `/restore`, `/restore dry-run`, `/restore project-only`.

### `/backup-status`

Runs `claude-backup list` and `claude-backup-banner` and summarizes the output
(how many backups, age of the latest, any warnings).

### `/backup-doctor`

Runs `claude-backup doctor` and interprets the result, calling out failures
first and then warnings with suggested fixes.

## Assumptions

- Commands use `allowed-tools: Bash(claude-backup:*)` (and friends) so they can
  invoke the installed CLI.
- `$ARGUMENTS` carries the raw keyword string; the command body performs the
  keyword→flag mapping.
- We do not auto-install the plugin from `install.sh` because there is no stable
  non-interactive "install this directory permanently" command; `install.sh`
  prints the two supported install paths instead.
