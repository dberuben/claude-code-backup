# Banner

`claude-backup-banner` prints a compact two-line status line summarizing the
current project, environment and backup health. It is safe to call from a shell
prompt, a status bar, or Claude Code — all detection degrades silently (missing
git, missing `kubectl`, missing backups never cause an error).

## Examples

A healthy, recently-backed-up project:

```
(⎈ grapetrack|prod) → claude-code-backup
◐ backup: 2h ago · mcp: ok · config: ok
```

No backup yet (note the warning glyph and `never`):

```
(⎈ grapetrack|prod) → claude-code-backup
⚠ backup: never · mcp: ok · config: check
```

Reading the lines:

- **Line 1** — `(⎈ <project>|<env>) → <directory> (<git-branch>)`
  - `<project>`: git repository name (or the directory name), or a fixed
    `BANNER_PROJECT_NAME`.
  - `<env>`: detected environment (see below).
  - `<directory>`: the current directory's name.
  - `(<git-branch>)`: appended when inside a git repo and `BANNER_SHOW_GIT=true`.
- **Line 2** — `<glyph> backup: <age> · mcp: <ok|none> · config: <ok|check>`
  - glyph is `◐` normally, `⚠` when there is no backup or the latest backup is
    older than `BANNER_MAX_BACKUP_AGE_HOURS`.

## Configuration

The banner reads `$HOME/.claude-backup/banner.conf` (override the path with the
`CCB_BANNER_CONF` environment variable). Start from
[`config/banner.example.conf`](../config/banner.example.conf). The file is
sourced as shell, so use `KEY=value` with no spaces around `=`.

| Key | Default | Meaning |
|-----|---------|---------|
| `BANNER_ENABLED` | `true` | Master switch; `false` prints nothing. |
| `BANNER_SHOW_GIT` | `true` | Append the git branch to line 1. |
| `BANNER_SHOW_ENV` | `true` | Show the `|env` segment on line 1. |
| `BANNER_SHOW_BACKUP_STATUS` | `true` | Show `backup: <age>` on line 2. |
| `BANNER_SHOW_MCP_STATUS` | `true` | Show `mcp: ok/none` on line 2. |
| `BANNER_SHOW_SECRET_WARNING` | `true` | Show `config: ok/check` on line 2. |
| `BANNER_STYLE` | `compact` | Layout (only `compact` is implemented). |
| `BANNER_PROJECT_NAME_AUTO` | `true` | Derive project name from git/dir. |
| `BANNER_PROJECT_NAME` | *(empty)* | Fixed name when `…_AUTO=false`. |
| `BANNER_ENV_AUTO` | `true` | Auto-detect the environment. |
| `BANNER_ENV` | *(empty)* | Fixed environment when `…_AUTO=false`. |
| `BANNER_MAX_BACKUP_AGE_HOURS` | `24` | Age beyond which backups are flagged. |

## Environment detection

When `BANNER_ENV_AUTO=true`, the environment is resolved in this order (first
hit wins), falling back to `local`:

1. `$CLAUDE_ENV`, then `$ENV`, then `$APP_ENV`, then `$NODE_ENV`
2. the current **Kubernetes context** name (only if `kubectl` exists — never
   required; skipped silently otherwise)
3. the **git branch** name, if it contains `prod`, `stage`/`staging`, `dev` or `trial`
4. the **current path**, matched the same way
5. `local`

## MCP and config status

- **`mcp: ok`** when `./.mcp.json` exists in the current project **or**
  `~/.claude.json` exists; otherwise **`mcp: none`**.
- **`config: check`** when any of `./.mcp.json`,
  `./.claude/settings.local.json` or `~/.claude.json` matches the secret
  heuristic; otherwise **`config: ok`**. The banner never prints the secret.

## Shell prompt integration

Run it once per prompt. For example, in **bash** (`~/.bashrc`):

```bash
# Print the banner above each prompt (only in interactive shells).
PROMPT_COMMAND='claude-backup-banner 2>/dev/null; '"${PROMPT_COMMAND:-}"
```

In **zsh** (`~/.zshrc`):

```zsh
precmd() { claude-backup-banner 2>/dev/null }
```

Prefer it on demand instead? Just add an alias:

```bash
alias ccb-status='claude-backup-banner'
```

## Claude Code integration

There is no supported API for Claude Code to render arbitrary text in its own
prompt area, so the banner is exposed through the plugin's
[`/backup-status`](plugin.md) command, which runs `claude-backup list` and
`claude-backup-banner` and summarizes the result. If a future Claude Code
release adds a status-line/hook surface, the same `claude-backup-banner` output
can be wired into it unchanged.
