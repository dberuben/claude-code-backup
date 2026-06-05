# Restore safety

Restore is the only operation that *writes outside* the backup directory, so it
is deliberately conservative. This document describes the guarantees and the
order in which `claude-restore` enforces them (see `lib/restore.sh`).

## The restore pipeline

1. **Select the archive.** `--from <archive>` if given, otherwise the newest
   `claude-code-backup-*.tar.gz` in the backup directory. Missing/invalid paths
   abort immediately.

2. **Validate the archive listing.** `tar -tzf` is inspected before anything is
   extracted. The restore is **refused** if any entry:
   - is an **absolute path** (`/...`), or
   - contains a **parent reference** (`..`, `../x`, `x/../y`, `x/..`).

   Entries outside the expected `manifest.txt` / `home/` / `project/` trees are
   warned about and ignored on restore.

3. **Extract to a temporary directory.** Files are unpacked into a fresh
   `mktemp -d`, **never** straight into `$HOME` or the project. The temp dir is
   removed via a `trap … EXIT` on every exit path.

4. **Reject escaping symlinks.** After extraction, every symlink in the tree is
   checked; if its target is absolute or contains `..` (i.e. it could point
   outside the staging dir), the restore is **refused**. This blocks the
   classic "symlink then write through it" escape.

5. **Show the plan.** Each target is listed as `create:` (new) or
   `overwrite/merge:` (already exists). With `--dry-run` the command stops here
   and **changes nothing**.

6. **Confirm.** Unless `--force` is given, you must confirm interactively. When
   stdin is not a TTY (e.g. inside an automation), `confirm()` returns *no*, so
   an un-forced restore safely cancels rather than proceeding blindly.

7. **Pre-restore backup.** Unless `--no-backup-existing` is given, the current
   state of everything about to change is archived to
   `…/pre-restore/pre-restore-<timestamp>_<host>.tar.gz` first, so you can roll
   back.

8. **Apply by merging.** Directories are copied with `cp -R "$src/." "$dest/"`
   — i.e. contents are **merged** into the destination. Files present locally
   but absent from the backup are **left in place**; the tool never silently
   deletes your data.

## Scope flags

- `--home-only` restores only `~/.claude` and `~/.claude.json`.
- `--project-only` restores only the current project's files.
- The two are mutually exclusive.

## Cross-platform restores

Archives are platform-neutral (relative paths, plain tar/gzip), so a backup made
on macOS restores on Linux and vice versa. Only `file_mtime`/`file_size`
reporting differs by OS, and that is handled in `lib/platform.sh`.

## What restore cannot bring back

Some credentials do not live inside the backed-up files and therefore **cannot**
be restored:

- OS keychains / credential stores (macOS Keychain, libsecret, etc.)
- OAuth tokens managed by external helpers
- values that exist only in environment variables
- secrets in external files you did not include (`.env.claude`, `.envrc` are
  only included with `--include-env`)

After a restore, if Claude Code or an MCP server reports an auth error, simply
re-authenticate — your other settings, commands, agents, hooks and skills are
already back in place.

**Plugins.** Backups prune installed plugin *code* and marketplace clones by
default but keep the manifests (`plugins/installed_plugins.json`,
`plugins/known_marketplaces.json`). On a fresh machine Claude Code will report
`cache-miss` for those marketplaces until they are re-added. To make this easy,
`claude-restore` reads the restored manifests and writes
**`<backup-dir>/restore-plugins.txt`** containing ready-to-paste commands:

```text
/plugin marketplace add anthropics/claude-plugins-official
/plugin marketplace add https://github.com/you/your-marketplace.git
/reload-plugins
# …and explicit `/plugin install name@marketplace` lines as a fallback
```

Paste those into Claude Code, then run `/reload-plugins`. A backup made with
`--full` includes the plugin code and marketplace clones, so no recovery is
needed in that case.
