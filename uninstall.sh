#!/usr/bin/env bash
#
# uninstall.sh - Remove claude-code-backup from a prefix (default: ~/.local).
#
# NEVER deletes backup archives. Prompts before removing the banner config and
# before touching any Claude Code plugin files.
set -euo pipefail

PREFIX="$HOME/.local"
ASSUME_YES=0

usage() {
  cat <<'EOF'
uninstall.sh - remove claude-code-backup

USAGE:
  ./uninstall.sh [options]

OPTIONS:
  --prefix <path>   Install prefix to remove from (default: ~/.local)
  --yes             Do not prompt; remove optional items too
  --help            Show this help

NOTE: backup archives are never removed by this script.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)  PREFIX="${2:?--prefix needs a path}"; shift ;;
    --yes|-y)  ASSUME_YES=1 ;;
    --help|-h) usage; exit 0 ;;
    *)         echo "uninstall.sh: unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

ask() {  # ask <prompt> -> 0 if yes
  [ "$ASSUME_YES" = "1" ] && return 0
  [ -t 0 ] || return 1
  printf '%s [y/N] ' "$1"
  read -r a || a=""
  case "$a" in [yY]*) return 0 ;; *) return 1 ;; esac
}

BIN_DIR="$PREFIX/bin"
LIB_DIR="$PREFIX/share/claude-code-backup"

echo "==> Removing claude-code-backup from: $PREFIX"

for b in claude-backup claude-restore claude-backup-banner; do
  if [ -f "$BIN_DIR/$b" ]; then rm -f "$BIN_DIR/$b"; echo "    removed $BIN_DIR/$b"; fi
done

if [ -d "$LIB_DIR" ]; then
  rm -rf "$LIB_DIR"
  echo "    removed $LIB_DIR"
fi

# Completions
rm -f "$PREFIX/share/bash-completion/completions/claude-backup" \
      "$PREFIX/share/zsh/site-functions/_claude-backup" 2>/dev/null || true

# Banner config (prompt)
conf="$HOME/.claude-backup/banner.conf"
if [ -f "$conf" ]; then
  if ask "Remove banner config $conf?"; then
    rm -f "$conf"
    rmdir "$HOME/.claude-backup" 2>/dev/null || true
    echo "    removed $conf"
  else
    echo "    kept $conf"
  fi
fi

# Plugin (we never installed it into Claude Code automatically; just remind)
if ask "Did you install the Claude Code plugin and want removal instructions?"; then
  cat <<'EOF'
    To remove the plugin from Claude Code:
      - If installed via marketplace: /plugin uninstall claude-code-backup
      - If loaded via --plugin-dir: just stop passing that flag.
EOF
fi

echo "==> Done. Your backup archives were NOT touched."
