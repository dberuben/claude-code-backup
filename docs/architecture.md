# Architecture

`claude-code-backup` is a set of small Bash programs with no third-party
dependencies. It is split into thin executables (`bin/`) and a library of
sourced functions (`lib/`).

## Layering

```
bin/claude-backup          bin/claude-restore        bin/claude-backup-banner
   │  (arg parsing,            │  (arg parsing)            │  (renders banner)
   │   dispatch, doctor)       │                           │
   └──────────────┬───────────┴───────────────┬───────────┘
                  │ sources                    │
        ┌─────────▼─────────┐                  │
        │   lib/common.sh   │  version, logging, JSON, time/size,
        │                   │  backup-dir resolution, confirm()
        └───┬───────┬───────┘
            │       │ sources at load
   ┌────────▼─┐  ┌──▼──────────┐
   │platform. │  │ security.sh │   (always loaded by common.sh)
   │   sh     │  └─────────────┘
   └──────────┘
   lib/archive.sh   lib/restore.sh   lib/banner.sh  (loaded per entrypoint)
```

- **`lib/common.sh`** is sourced first by every entrypoint. It pulls in
  `platform.sh` and `security.sh` and defines shared state (`CCB_VERSION`,
  output mode, colors), logging (`log_*`, `die`), JSON escaping, time/size
  formatting, backup-directory resolution and `confirm()`.
- **`lib/platform.sh`** isolates every BSD-vs-GNU difference: `detect_platform`
  sets `CCB_PLATFORM` from `uname -s`, and `file_mtime` / `file_size` /
  `os_version` branch on it. **All** platform conditionals live
  here so the rest of the code stays portable.
- **`lib/security.sh`** is the heuristic secret scanner. It never prints secret
  values — only file paths and which pattern matched.
- **`lib/archive.sh`** builds the backup *plan*, stages files, writes the
  manifest, and creates the tarball. Entry point: `do_backup`.
- **`lib/restore.sh`** lists backups and performs the safety-checked restore.
  Entry points: `do_list`, `do_restore`. See [restore-safety.md](restore-safety.md).
- **`lib/banner.sh`** renders the status line. Entry point: `render_banner`.

## How a binary finds its libraries

Each `bin/` script begins with a small bootstrap that resolves its own location
(following symlinks portably, since macOS has no `readlink -f`) and then probes,
in order:

1. `$CLAUDE_BACKUP_LIB` (explicit override, used by the test suite)
2. `<self>/../lib` — running straight from a repo checkout
3. `<self>/../share/claude-code-backup/lib` — installed layout
4. `$HOME/.local/share/claude-code-backup/lib` — default install fallback

This is why the same binary works unmodified whether you run it from the cloned
repo or after `install.sh`.

## Archive format

A backup is a gzip-compressed tar with **relative** paths only:

```
manifest.txt
home/.claude/...
home/.claude.json
project/.claude/...
project/.mcp.json
project/CLAUDE.md
project/CLAUDE.local.md
```

Filename: `claude-code-backup-YYYY-MM-DD_HH-MM-SS_HOSTNAME.tar.gz`.

**Staging without copying.** A real `~/.claude` can be multiple gigabytes, so
the backup never copies data to a temp dir. Instead `build_stage` creates a
`mktemp -d` containing only **symlinks** to the top-level sources
(`home/.claude -> ~/.claude`, etc.), then archives with `tar -czh -C <stage> .`.
The `-h` flag dereferences the symlinks so real contents are stored under
relative paths (`home/…`, `project/…`, `manifest.txt`) — no absolute or `..`
components, and the data is read+compressed exactly once.

**Pruning (`lib/common.sh: CCB_EXCLUDE_NAMES`, `archive.sh: ccb_tar_excludes`).**
Large/ephemeral directory names (plugin `cache`/`marketplaces`, `telemetry`,
`site-packages`, `node_modules`, …) are pruned via `tar --exclude` patterns
(`NAME` for bsdtar's basename match plus `*/NAME` for GNU tar's nested match),
which prune at *any depth* in tar's single pass — no manual tree walk.
`projects/` (history) is kept by default and dropped with `--no-history`;
`--full` disables all pruning. The small plugin manifests are always kept so a
restore knows which plugins/marketplaces to reinstall.

The manifest records timestamps (UTC + local), host/user, platform, OS version,
shell, Claude Code version (or `not found`), git repo/branch, and the
included/skipped/pruned/warning lists.

## Design rules

- The CLI must work with Claude Code absent or broken; `claude --version`
  failing is recorded as `not found`, never fatal.
- No network calls, no uploads, no telemetry, no auto-update.
- POSIX-friendly Bash; runs under bash 3.2 (the macOS system bash).
- All variables quoted; paths-with-spaces safe; temp dirs cleaned via `trap`.
