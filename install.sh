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

# Where this script's sources live. Empty/invalid when piped via `curl | bash`,
# in which case we bootstrap by downloading the repo below.
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

# Repo coordinates for the curl|bash bootstrap (override via env).
CCB_REPO="${CCB_REPO:-dberuben/claude-code-backup}"
CCB_REF="${CCB_REF:-main}"

BOOTSTRAP_TMP=""
# Note the trailing `return 0`: without it the handler's last command is the
# `[ -n "$BOOTSTRAP_TMP" ]` test, which is false (status 1) on the normal local
# install, and an EXIT trap's last status overrides the script's exit code —
# making a successful install exit 1 and failing CI.
cleanup_bootstrap() { [ -n "$BOOTSTRAP_TMP" ] && rm -rf "$BOOTSTRAP_TMP"; return 0; }
trap cleanup_bootstrap EXIT

usage() {
  cat <<'EOF'
install.sh - install claude-code-backup

USAGE:
  ./install.sh [options]
  curl -fsSL https://raw.githubusercontent.com/dberuben/claude-code-backup/main/install.sh | bash

OPTIONS:
  --prefix <path>     Install prefix (default: ~/.local)
  --no-completions    Do not install shell completions
  --no-banner-conf    Do not install the example banner config
  --yes               Do not prompt (assume yes for optional steps)
  --help              Show this help

ENV (curl|bash bootstrap):
  CCB_REPO   owner/name to download from (default: dberuben/claude-code-backup)
  CCB_REF    branch or tag to install     (default: main)
EOF
}

# bootstrap_sources - when running without a local checkout (piped via curl),
# download the repo tarball for CCB_REF and point SRC_DIR at the extracted tree.
bootstrap_sources() {
  local url dl
  url="https://github.com/$CCB_REPO/archive/$CCB_REF.tar.gz"   # works for branch or tag
  echo "==> No local sources found; downloading $CCB_REPO@$CCB_REF…"
  BOOTSTRAP_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ccb-install.XXXXXX")" || { echo "install.sh: mktemp failed" >&2; exit 1; }

  if command -v curl >/dev/null 2>&1; then
    dl="curl -fsSL"
  elif command -v wget >/dev/null 2>&1; then
    dl="wget -qO-"
  else
    echo "install.sh: need curl or wget to bootstrap (or run from a git checkout)" >&2
    exit 1
  fi

  if ! $dl "$url" | tar xz -C "$BOOTSTRAP_TMP"; then
    echo "install.sh: download/extract failed: $url" >&2
    exit 1
  fi
  SRC_DIR="$(find "$BOOTSTRAP_TMP" -maxdepth 1 -type d -name 'claude-code-backup-*' 2>/dev/null | head -n1)"
  [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/lib/common.sh" ] \
    || { echo "install.sh: unexpected archive layout from $url" >&2; exit 1; }
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

# If we are not sitting in a checkout (e.g. piped via curl|bash), fetch sources.
if [ -z "$SRC_DIR" ] || [ ! -f "$SRC_DIR/lib/common.sh" ] || [ ! -f "$SRC_DIR/bin/claude-backup" ]; then
  bootstrap_sources
fi

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
