# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Default backup pruning of large/ephemeral directories (plugin code/caches,
  telemetry, venvs, `node_modules`, …) at any depth, keeping the small plugin
  manifests so restore knows what to reinstall. New `--full` (keep everything)
  and `--no-history` (drop `projects/`) flags, plus `full`/`no-history`
  keywords for the `/backup` slash command.
- Live progress indicator while archiving.
- GitHub Actions CI (`.github/workflows/ci.yml`): ShellCheck + full test suite
  + install smoke test on Ubuntu and macOS (the macOS runner also exercises the
  system bash 3.2).
- `tests/test-compat.sh`: regression tests for empty-array handling under
  bash 3.2, graceful failure with no config, and the tightened secret scanner.

### Changed
- Staging now symlinks top-level sources and archives with `tar -czh` instead
  of copying gigabytes to a temp dir, so backups of a multi-GB `~/.claude` are
  fast.
- Tightened the secret scanner to match credential *formats* (provider key
  prefixes, JWTs, PEM headers, AWS keys) and `key = value` assignments rather
  than bare words, drastically reducing false positives (33 → 4 on a real
  `~/.claude`).

### Fixed
- Secret scanner no longer spawns a grep per file per pattern (which made
  `claude-backup` appear to hang on large `~/.claude` trees); it now uses a
  single recursive grep that skips the bulky/ephemeral directories.
- No longer crashes under bash 3.2 (macOS system bash) with "unbound variable"
  when an array is empty (e.g. `--full`, or a banner with all segments off);
  `claude-backup` now also fails cleanly when there is no config to back up.

## [0.1.0] - 2026-06-05

### Added
- `claude-backup` CLI: create backups of global (`~/.claude`, `~/.claude.json`)
  and project (`.claude/`, `.mcp.json`, `CLAUDE.md`, `CLAUDE.local.md`) config.
- `claude-backup` subcommands: `list`, `doctor`, `banner`.
- `claude-restore` CLI with a safety-first restore flow: archive validation,
  temp-dir extraction, symlink-escape rejection, restore plan, confirmation,
  and an automatic pre-restore backup.
- `claude-backup-banner`: compact two-line status line (project, environment,
  backup age, MCP status, secret warning) with a configurable `banner.conf`.
- Heuristic secret scanner (`--strict-secrets` to abort on detection).
- `--icloud` option to copy backups to iCloud Drive on macOS.
- `--json` machine-readable output for backup, list and restore.
- Claude Code plugin with `/backup`, `/restore`, `/backup-status`,
  `/backup-doctor` slash commands (convenience layer over the CLI).
- `install.sh` / `uninstall.sh`, bash + zsh completions.
- Cross-platform support for macOS (BSD tools) and Linux (GNU tools);
  verified to run under bash 3.2.
- Documentation: architecture, restore safety, banner, plugin; plus
  `SECURITY.md`, `CONTRIBUTING.md`.

[Unreleased]: https://github.com/YOUR_USERNAME/claude-code-backup/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/YOUR_USERNAME/claude-code-backup/releases/tag/v0.1.0
