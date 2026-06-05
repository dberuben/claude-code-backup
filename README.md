# claude-code-backup

A simple, safe, cross-platform backup & restore tool for [Claude Code](https://claude.com/claude-code).

It snapshots your Claude Code configuration — global settings, MCP configs,
slash commands, agents, hooks, skills and per-project files — into a single
`.tar.gz` you control, and restores it on the same or a new machine.

- **Standalone CLI** — `claude-backup`, `claude-restore`, plus `doctor`,
  `list` and `banner` subcommands. Works **even when Claude Code is not
  installed or not yet configured.**
- **Claude Code plugin** — `/backup`, `/restore`, `/backup-status`,
  `/backup-doctor` slash commands as a convenience layer over the CLI.
- **No dependencies** beyond standard `bash`, `tar`, `gzip`, `grep`, `sed`,
  `awk`, `find`, `date`, `uname`, `mktemp`. No `jq`, Python, Node or Homebrew.
- **macOS and Linux**, including macOS's system bash 3.2.
- **No network calls, no uploads, no telemetry, no auto-update.**

## Why this exists

Claude Code stores a surprising amount of valuable state in `~/.claude/` and
`~/.claude.json` (and per-project `.claude/`, `.mcp.json`, `CLAUDE.md`): MCP
servers, custom commands, agents, hooks, skills, project trust and preferences.
Reproducing that by hand on a new laptop is tedious and error-prone. This tool
makes it one command — without sending your config to anyone.

## Requirements

- macOS (`Darwin`) or Linux
- `bash` 3.2+ and the standard userland tools listed above

Check your machine any time with `claude-backup doctor`.

## Install

```bash
git clone https://github.com/YOUR_USERNAME/claude-code-backup.git
cd claude-code-backup
./install.sh
```

This installs to `~/.local` by default:

- binaries → `~/.local/bin`
- libraries → `~/.local/share/claude-code-backup/lib`
- completions → `~/.local/share/{bash-completion,zsh}`
- example banner config → `~/.claude-backup/banner.conf`

Make sure `~/.local/bin` is on your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"   # add to ~/.bashrc or ~/.zshrc
```

Custom prefix and options:

```bash
./install.sh --prefix /custom/path     # install elsewhere
./install.sh --no-completions          # skip shell completions
./install.sh --no-banner-conf          # skip example banner config
./install.sh --yes                     # non-interactive
```

You can also run the tools straight from the checkout without installing —
`bin/claude-backup` finds its libraries relative to itself.

## Quick start

On your existing machine:

```bash
claude-backup --icloud         # back up, and also copy to iCloud Drive (macOS)
```

On a new machine:

```bash
git clone https://github.com/YOUR_USERNAME/claude-code-backup.git
cd claude-code-backup
./install.sh
claude-restore                 # restores from your latest backup
```

After restore, Claude Code recovers most user configs, MCP configs, slash
commands, agents, hooks, skills and project settings. Some credentials may need
re-authentication (see [What is NOT backed up](#what-is-not-backed-up)).

## Backup examples

```bash
claude-backup                          # global + current project → ~/Backups/claude-code
claude-backup --dry-run                # show what would be backed up, write nothing
claude-backup --no-project             # only global (~/.claude, ~/.claude.json)
claude-backup --no-history             # skip projects/ (conversation history; large)
claude-backup --full                   # include EVERYTHING (no pruning; can be many GB)
claude-backup --dest /mnt/usb/ccb      # choose the destination directory
claude-backup --include-env            # also include .env.claude / .envrc (secrets!)
claude-backup --strict-secrets         # abort if likely secrets are detected
claude-backup --json                   # machine-readable output
claude-backup list                     # list existing backups
claude-backup list --json
```

Destination precedence: `--dest` › `$CLAUDE_BACKUP_DIR` › `~/Backups/claude-code`.

Archive name: `claude-code-backup-YYYY-MM-DD_HH-MM-SS_HOSTNAME.tar.gz`.

### iCloud (macOS)

```bash
claude-backup --icloud
```

Writes the archive to `~/Backups/claude-code` **and** copies it to
`~/Library/Mobile Documents/com~apple~CloudDocs/claude-code-backup/`. On Linux
the flag is accepted but skipped with a notice.

> ⚠️ iCloud syncs the archive — which may contain secrets — to Apple's servers
> and all your devices. Only use `--icloud` if that is acceptable to you.

### Linux storage example

There is no iCloud on Linux; point backups at any directory you like — an
encrypted volume, a synced folder, or a USB stick:

```bash
export CLAUDE_BACKUP_DIR="$HOME/Nextcloud/claude-code"   # or any path
claude-backup
# or one-off:
claude-backup --dest /media/$USER/usbkey/claude-code
```

## Restore examples

```bash
claude-restore                         # restore latest backup (interactive)
claude-restore --list                  # list available backups
claude-restore --from <archive.tar.gz> # restore a specific archive
claude-restore --dry-run               # show the restore plan only
claude-restore --home-only             # only ~/.claude + ~/.claude.json
claude-restore --project-only          # only current project's files
claude-restore --force                 # skip the confirmation prompt
claude-restore --no-backup-existing    # skip the automatic pre-restore backup
```

Restore is conservative by default: it validates the archive, extracts to a
temp directory, shows a plan, asks for confirmation, and takes a pre-restore
backup before changing anything. See [docs/restore-safety.md](docs/restore-safety.md).

## Banner

A compact status line for your shell or Claude Code:

```
(⎈ grapetrack|prod) → claude-code-backup
◐ backup: 2h ago · mcp: ok · config: ok
```

```bash
claude-backup-banner                   # or: claude-backup banner
```

Configure it via `~/.claude-backup/banner.conf` (copy from
[`config/banner.example.conf`](config/banner.example.conf)). To show it above
every prompt:

```bash
# bash ~/.bashrc
PROMPT_COMMAND='claude-backup-banner 2>/dev/null; '"${PROMPT_COMMAND:-}"
# zsh ~/.zshrc
precmd() { claude-backup-banner 2>/dev/null }
```

Full details and every config key: [docs/banner.md](docs/banner.md).

## Claude Code plugin

The plugin wraps the CLI in slash commands. Install it for local development:

```bash
claude --plugin-dir /path/to/claude-code-backup/plugin
```

…or share it via a marketplace (see [docs/plugin.md](docs/plugin.md)):

```bash
/plugin marketplace add https://github.com/YOUR_USERNAME/claude-code-backup
/plugin install claude-code-backup@claude-code-backup
```

Commands:

| Command | Runs |
|---------|------|
| `/backup [icloud] [dry-run] [no-project] [strict-secrets] [include-env]` | `claude-backup` |
| `/restore [dry-run] [home-only] [project-only]` | `claude-restore` (never `--force` automatically) |
| `/backup-status` | `claude-backup list` + `claude-backup-banner` |
| `/backup-doctor` | `claude-backup doctor` |

The plugin requires the CLI on your `PATH`. The CLI never requires the plugin.

## Security warnings

**Backups can contain live secrets** — Claude credentials, MCP tokens, OAuth
state, API keys, local paths, project trust settings and private instructions.

- **Never commit backups to git** (the repo's `.gitignore` excludes `*.tar.gz`,
  `Backups/`, `pre-restore/`, `.env*`).
- Store archives on encrypted storage, or encrypt them (e.g. `gpg --symmetric`).
- A built-in heuristic scanner warns about likely secrets; `--strict-secrets`
  turns warnings into a hard stop. It never prints the secret value.

Read [SECURITY.md](SECURITY.md) before sharing or syncing any archive.

## What is backed up

Global (always, unless excluded):

- `~/.claude/` — settings, slash commands, agents, hooks, skills, etc.
- `~/.claude.json`

Project (current working directory; included by default, disable with `--no-project`):

- `.claude/`
- `.mcp.json`
- `CLAUDE.md`
- `CLAUDE.local.md`

Only with `--include-env` (because they often hold secrets):

- `.env.claude`
- `.envrc`

Each archive also contains a `manifest.txt` describing when/where/how it was made.

### Default scope and pruning

A real `~/.claude` is frequently **several gigabytes** — most of it large,
regenerable data. By default the backup **prunes** these directory names at any
depth (so a backup stays focused and fast):

```
cache  marketplaces  npm-cache  plugin-catalog-cache.json  telemetry  debug
paste-cache  statsig  shell-snapshots  file-history  tmp  logs
node_modules  site-packages  __pycache__  venv  .venv  .DS_Store
```

What this means in practice:

- **Conversation history (`projects/`) IS backed up by default.** Use
  `--no-history` to skip it for a much smaller archive.
- **Installed plugin *code* is pruned** (`plugins/cache`, `plugins/marketplaces`,
  …) but the small **manifests are kept** (`plugins/installed_plugins.json`,
  `plugins/known_marketplaces.json`) so you know exactly which plugins and
  marketplaces to reinstall — see below.
- Use **`--full`** to disable all pruning and archive everything verbatim.

The backup prints a live progress indicator while archiving and lists what it
pruned; the full pruned list is also recorded in the archive's `manifest.txt`.

## What is NOT backed up

- Secrets held **outside** the backed-up files: OS keychains/credential stores
  (macOS Keychain, libsecret…), OAuth tokens kept by external helpers, and
  values living only in environment variables.
- **Installed plugin/marketplace code** (pruned by default — it is large and
  re-downloadable). The manifests that list *what* was installed are kept.
- Arbitrary other files in your project.
- Anything you exclude via `--no-project`, `--no-history`, or omit by not
  passing `--include-env` / `--full`.

After a restore you may need to re-authenticate Claude Code or specific MCP
servers; the rest of your configuration is restored verbatim.

### Reinstalling plugins after a restore

Because plugin code is pruned, reinstall it after restoring. The kept manifests
tell you what you had:

```bash
# which marketplaces you had subscribed to:
cat ~/.claude/plugins/known_marketplaces.json
# which plugins were installed:
cat ~/.claude/plugins/installed_plugins.json
```

Then, in Claude Code, re-add each marketplace and reinstall each plugin:

```
/plugin marketplace add <url-from-known_marketplaces.json>
/plugin install <name>@<marketplace>
```

(If you ran `claude-backup --full`, the plugin code was backed up too and no
reinstall is needed.)

## Known limitations

- Restore **merges** directories (it never deletes files missing from the
  backup), so a restored `~/.claude` may retain extra local files.
- The secret scanner is heuristic: expect occasional false positives and the
  possibility of missing novel token formats.
- Backups are not encrypted by the tool itself — you choose the storage.
- The banner's `BANNER_STYLE` currently supports only `compact`.
- Claude Code has no public API for custom prompt text, so the banner is
  surfaced through `/backup-status` rather than the native prompt area.

## Troubleshooting

- **`claude-backup: command not found`** — `~/.local/bin` isn't on your `PATH`.
  Add `export PATH="$HOME/.local/bin:$PATH"` to your shell profile, or run from
  the checkout (`./bin/claude-backup`).
- **`cannot locate lib dir`** — you moved the binary away from its libraries.
  Reinstall, or set `CLAUDE_BACKUP_LIB=/path/to/lib`.
- **Restore says "refusing to restore an unsafe archive"** — the archive
  contains absolute or `..` paths and was rejected on purpose; only restore
  archives produced by this tool.
- **`--icloud` did nothing** — you're on Linux, or iCloud Drive isn't set up;
  the flag is skipped with a notice. Use `--dest`/`$CLAUDE_BACKUP_DIR` instead.
- **MCP/auth errors after restore** — re-authenticate; some tokens live outside
  the backup (see above).
- Run `claude-backup doctor` for a full environment report.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). In short: simple portable shell, runs on
macOS + Linux + bash 3.2, ShellCheck-clean, tests pass (`bash tests/run.sh`),
Conventional Commits.

## License

[MIT](LICENSE) © claude-code-backup contributors.
