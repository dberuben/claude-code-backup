#!/usr/bin/env bash
#
# install.sh - Install claude-code-backup into a prefix (default: ~/.local).
#
# Layout after install:
#   <prefix>/bin/{claude-backup,claude-restore,claude-backup-banner}
#   <prefix>/share/claude-code-backup/lib/*.sh
#
# The bin scripts locate their libraries via "<self>/../share/claude-code-backup/lib",
# so this layout works without any environment variables.
#
# Idempotent. Never deletes backups. Supports macOS and Linux.
set -euo pipefail

PREFIX="$HOME/.local"
INSTALL_COMPLETIONS=1
INSTALL_BANNER_CONF=1
ASSUME_YES=0

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
install.sh - install claude-code-backup

USAGE:
  ./install.sh [options]

OPTIONS:
  --prefix <path>     Install prefix (default: ~/.local)
  --no-completions    Do not install shell completions
  --no-banner-conf    Do not install the example banner config
  --yes               Do not prompt (assume yes for optional steps)
  --help              Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)         PREFIX="${2:?--prefix needs a path}"; shift ;;
    --no-completions) INSTALL_COMPLETIONS=0 ;;
    --no-banner-conf) INSTALL_BANNER_CONF=0 ;;
    --yes|-y)         ASSUME_YES=1 ;;
    --help|-h)        usage; exit 0 ;;
    *)                echo "install.sh: unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

BIN_DIR="$PREFIX/bin"
LIB_DIR="$PREFIX/share/claude-code-backup/lib"

echo "==> Installing claude-code-backup to: $PREFIX"

mkdir -p "$BIN_DIR" "$LIB_DIR"

# --- libraries -------------------------------------------------------------
for f in "$SRC_DIR"/lib/*.sh; do
  install_to="$LIB_DIR/$(basename "$f")"
  cp "$f" "$install_to"
  chmod 0644 "$install_to"
done
echo "    libraries -> $LIB_DIR"

# --- binaries --------------------------------------------------------------
for b in claude-backup claude-restore claude-backup-banner; do
  cp "$SRC_DIR/bin/$b" "$BIN_DIR/$b"
  chmod 0755 "$BIN_DIR/$b"
done
echo "    binaries  -> $BIN_DIR"

# --- shell completions -----------------------------------------------------
if [ "$INSTALL_COMPLETIONS" = "1" ]; then
  comp_base="$PREFIX/share"
  mkdir -p "$comp_base/bash-completion/completions" "$comp_base/zsh/site-functions"
  cp "$SRC_DIR/completions/claude-backup.bash" "$comp_base/bash-completion/completions/claude-backup"
  cp "$SRC_DIR/completions/claude-backup.zsh"  "$comp_base/zsh/site-functions/_claude-backup"
  echo "    completions installed under $comp_base"
fi

# --- example banner config -------------------------------------------------
if [ "$INSTALL_BANNER_CONF" = "1" ]; then
  conf_dir="$HOME/.claude-backup"
  conf="$conf_dir/banner.conf"
  mkdir -p "$conf_dir"
  if [ -f "$conf" ]; then
    echo "    banner config already exists (left untouched): $conf"
  else
    do_copy=1
    if [ "$ASSUME_YES" != "1" ] && [ -t 0 ]; then
      printf '    Install example banner config to %s? [Y/n] ' "$conf"
      read -r ans || ans=""
      case "$ans" in [nN]*) do_copy=0 ;; esac
    fi
    if [ "$do_copy" = "1" ]; then
      cp "$SRC_DIR/config/banner.example.conf" "$conf"
      echo "    banner config -> $conf"
    fi
  fi
fi

# --- PATH check ------------------------------------------------------------
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "==> NOTE: $BIN_DIR is not on your PATH."
     echo "    Add this to your shell profile:"
     echo "        export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

# --- Claude Code plugin guidance ------------------------------------------
cat <<EOF
==> Done.

Claude Code plugin (optional, convenience layer over the CLI):
  The plugin lives in: $SRC_DIR/plugin
  Install it for local development with:
      claude --plugin-dir "$SRC_DIR/plugin"
  Or distribute via a marketplace (see docs/plugin.md). The CLI works fully
  without the plugin.

Try it:
  claude-backup doctor
EOF
