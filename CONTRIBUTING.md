# Contributing to claude-code-backup

Thanks for your interest! This project values **simple, readable, portable**
shell over clever shell. Contributions of any size are welcome.

## Principles

- **The CLI is the product.** The Claude Code plugin is a thin convenience
  layer; it must never become a dependency of backup or restore.
- **Restore is safety-critical.** Changes to `lib/restore.sh` get extra
  scrutiny. Never weaken the archive validation or the pre-restore backup.
- **Portability first.** Code must run on macOS (BSD tools) and Linux (GNU
  tools), and under bash 3.2. Avoid `jq`, Python, Node, Homebrew, `gsed`,
  `gtar`, and GNU-only flags. Branch on `CCB_PLATFORM` when tools differ.
- **No network, no telemetry, no auto-update, no uploads.** Ever.

## Development setup

```bash
git clone https://github.com/dberuben/claude-code-backup.git
cd claude-code-backup
./install.sh --prefix "$PWD/.dev"      # optional; or just run bin/ directly
bash tests/run.sh                      # run the full suite
```

You do **not** need Claude Code installed to develop or test.

## Coding standards

- `#!/usr/bin/env bash` and `set -euo pipefail` in every executable.
- Quote all expansions; assume paths contain spaces.
- Prefer functions; keep global mutable state minimal (we prefix ours `CCB_`/`OPT_`).
- Beware the classic `set -e` trap: a function whose **last** statement is a
  bare `[ ... ] && ...` returns non-zero and aborts the caller. End such
  functions with `return 0`.
- Clean up temp files with `mktemp -d` + `trap ... EXIT`.
- Never print a secret's value. Never silently overwrite or delete.
- Comment around dangerous restore logic.

## Linting and tests

```bash
shellcheck -x bin/* lib/*.sh install.sh uninstall.sh tests/*.sh
bash tests/run.sh
```

Both must be clean before you open a PR. Add a test for any behavior change;
tests use temporary fake homes/projects and must not require real Claude Code.

## Commit messages (Conventional Commits)

Use the [Conventional Commits](https://www.conventionalcommits.org/) format:

```
feat(banner): add BANNER_STYLE=verbose layout
fix(restore): reject symlinks with absolute targets
docs(readme): clarify synced-folder security implications
test(backup): cover --include-env path
chore(release): bump version to 0.2.0
```

Common types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `ci`.

## Pull requests

1. Branch from `main`.
2. Keep PRs focused; describe the user-visible change and the risk.
3. Update `CHANGELOG.md` under `[Unreleased]`.
4. Ensure ShellCheck and `tests/run.sh` pass on macOS and Linux if you can.

## Releasing (maintainers)

1. Move `[Unreleased]` notes into a new version section in `CHANGELOG.md`.
2. Bump `CCB_VERSION` in `lib/common.sh` and `version` in
   `plugin/.claude-plugin/plugin.json` (and the marketplace entry).
3. Tag `vX.Y.Z` and create a GitHub release.
