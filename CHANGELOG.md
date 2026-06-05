# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Restore now warns when Claude Code appears to be running (quit it first).
- After a restore, `claude-restore` writes `<backup-dir>/restore-plugins.txt`
  with ready-to-paste `/plugin marketplace add …` + `/plugin install …` +
  `/reload-plugins` commands derived from the restored plugin manifests, so a
  new machine can recover its plugins (which aren't part of the backup).

### Changed
- Restore's pre-restore snapshot uses the fast symlink + `tar -czh` + pruning
  path (no multi-GB `cp -R`), matching the main backup.
- Restore plan distinguishes `overwrite:` (single files, a revert) from
  `merge into:` (directories) so the effect is clear.
- README trimmed to the essentials; full detail lives in `docs/`.

## [0.1.0] - 2026-06-05

First release.

### Added
- `claude-backup` CLI: back up global (`~/.claude`, `~/.claude.json`) and
  current-project (`.claude/`, `.mcp.json`, `CLAUDE.md`, `CLAUDE.local.md`)
  Claude Code config into a single `.tar.gz`. Subcommands: `list`, `doctor`,
  `banner`. Options include `--dest`, `--no-project`, `--no-history`, `--full`,
  `--include-env`, `--strict-secrets`, `--dry-run`, `--json`, `--quiet`.
- `claude-restore` CLI with a safety-first flow: archive-listing validation,
  temp-dir extraction, symlink-escape rejection, a shown plan, confirmation
  (interactive unless `--force`), and an automatic pre-restore backup. Supports
  `--from`, `--home-only`, `--project-only`, `--dry-run`, `--list`, `--json`.
- `claude-backup-banner`: compact two-line status line (project, environment,
  backup age, MCP status, secret check) with a configurable `banner.conf`.
- Default pruning of large/ephemeral directories (plugin code/caches,
  telemetry, venvs/`site-packages`, `node_modules`, …) at any depth, while
  keeping the small plugin manifests so restore knows what to reinstall;
  `--no-history` drops `projects/`, `--full` keeps everything.
- Heuristic secret scanner matching credential *formats* (provider key
  prefixes, JWTs, PEM headers, AWS keys) and `key = value` assignments;
  warns by default, aborts with `--strict-secrets`, never prints values.
- Live progress indicator while archiving; interrupt-safe (Ctrl-C/kill stops
  the in-flight tar and removes the partial archive + staging dir).
- Claude Code plugin with `/backup`, `/restore`, `/backup-status`,
  `/backup-doctor` slash commands (convenience layer over the CLI).
- `install.sh` / `uninstall.sh`, bash + zsh completions.
- Cross-platform: macOS (BSD tools) and Linux (GNU tools); runs under bash 3.2.
- GitHub Actions CI (ShellCheck + full test suite + install smoke test on
  Ubuntu and macOS); 57-test suite.
- Documentation: architecture, restore safety, banner, plugin; plus
  `SECURITY.md`, `CONTRIBUTING.md`.

[Unreleased]: https://github.com/dberuben/claude-code-backup/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/dberuben/claude-code-backup/releases/tag/v0.1.0
