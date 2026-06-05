# shellcheck shell=bash
#
# common.sh - Shared state, logging, and helpers for claude-code-backup.
#
# This is the first library sourced by every bin/ entrypoint. It pulls in the
# other libraries and establishes global configuration (version, output mode,
# colors, backup directory resolution).
#
# Sourced, never executed directly.

# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------
CCB_VERSION="0.1.0"

# ---------------------------------------------------------------------------
# Library loading
# ---------------------------------------------------------------------------
# CCB_LIB_DIR is set by the bootstrap in each bin/ script before sourcing us.
: "${CCB_LIB_DIR:?CCB_LIB_DIR must be set before sourcing common.sh}"

# shellcheck source=platform.sh
. "$CCB_LIB_DIR/platform.sh"
# shellcheck source=security.sh
. "$CCB_LIB_DIR/security.sh"

detect_platform

# ---------------------------------------------------------------------------
# Output mode + colors
# ---------------------------------------------------------------------------
# These are mutated by argument parsing in the bin scripts.
CCB_QUIET="${CCB_QUIET:-0}"
CCB_JSON="${CCB_JSON:-0}"

# Enable colors only on an interactive terminal and when NO_COLOR is unset.
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

# All human-facing logging goes to stderr so that --json output on stdout stays
# clean and machine-parseable.
log_info() { [ "$CCB_QUIET" = "1" ] && return 0; printf '%s\n' "$*" >&2; }
log_step() { [ "$CCB_QUIET" = "1" ] && return 0; printf '%s==>%s %s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$*" >&2; }
log_ok()   { [ "$CCB_QUIET" = "1" ] && return 0; printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
log_warn() { printf '%s⚠ %s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
log_err()  { printf '%s✗ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }

# die <message> - print an error and exit non-zero.
die() { log_err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# JSON helpers (no jq dependency)
# ---------------------------------------------------------------------------
# json_escape <string> - escape a string for safe inclusion in a JSON value.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"   # backslash first
  s="${s//\"/\\\"}"   # double quote
  s="${s//	/\\t}"    # tab
  # Replace newlines with \n via awk-free parameter expansion is not possible,
  # so use printf|sed for embedded newlines.
  if printf '%s' "$s" | grep -q '
'; then
    s="$(printf '%s' "$s" | sed ':a;N;$!ba;s/\n/\\n/g')"
  fi
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# Time + size formatting
# ---------------------------------------------------------------------------
# now_epoch - current time as Unix epoch seconds.
now_epoch() { date +%s; }

# utc_timestamp - ISO-8601 UTC timestamp.
utc_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# local_timestamp - local timestamp suitable for filenames.
local_timestamp() { date +"%Y-%m-%d_%H-%M-%S"; }

# human_age <seconds> - turn a duration in seconds into a compact "2h", "3d" form.
human_age() {
  local s="$1"
  if [ -z "$s" ] || [ "$s" -lt 0 ] 2>/dev/null; then printf 'unknown'; return; fi
  if   [ "$s" -lt 60 ];     then printf '%ds' "$s"
  elif [ "$s" -lt 3600 ];   then printf '%dm' "$((s / 60))"
  elif [ "$s" -lt 86400 ];  then printf '%dh' "$((s / 3600))"
  else                           printf '%dd' "$((s / 86400))"
  fi
}

# human_size <bytes> - format a byte count as B/K/M/G.
human_size() {
  local b="$1"
  if [ -z "$b" ]; then printf 'unknown'; return; fi
  if   [ "$b" -lt 1024 ];        then printf '%dB' "$b"
  elif [ "$b" -lt 1048576 ];     then printf '%dK' "$((b / 1024))"
  elif [ "$b" -lt 1073741824 ];  then printf '%dM' "$((b / 1048576))"
  else                                printf '%dG' "$((b / 1073741824))"
  fi
}

# ---------------------------------------------------------------------------
# Backup scope / exclusions
# ---------------------------------------------------------------------------
# Entry names (matched by basename, at ANY depth) that are large, ephemeral or
# trivially regenerable. They are pruned from backups by default; `--full`
# disables all pruning. Note we do NOT prune the whole `plugins/` dir — only
# its bulky sub-dirs (cache/marketplaces/npm-cache) and the catalog cache file
# — so the small `installed_plugins.json` / `known_marketplaces.json` manifests
# are kept and restore knows which plugins to reinstall.
CCB_EXCLUDE_NAMES="cache marketplaces npm-cache plugin-catalog-cache.json telemetry debug paste-cache statsig shell-snapshots file-history tmp logs node_modules site-packages __pycache__ venv .venv .DS_Store"

# `projects/` (conversation history, often gigabytes) is included by default
# but pruned when --no-history is given. The secret scanner always skips the
# excluded dirs above and projects regardless, since scanning gigabytes of
# transcripts is slow and noisy — the scanner targets config, not logs.
OPT_FULL="${OPT_FULL:-0}"
OPT_NO_HISTORY="${OPT_NO_HISTORY:-0}"

# ccb_is_excluded <name> - return 0 if an entry (at any depth) should be pruned.
ccb_is_excluded() {
  local name="$1" e
  [ "${OPT_FULL:-0}" = "1" ] && return 1   # --full keeps everything
  for e in $CCB_EXCLUDE_NAMES; do
    [ "$name" = "$e" ] && return 0
  done
  [ "${OPT_NO_HISTORY:-0}" = "1" ] && [ "$name" = "projects" ] && return 0
  return 1
}

# ccb_tar_excludes - echo the tar --exclude flags (one per line) for the pruned
# names under the current options. Empty under --full. For each NAME we emit
# both `NAME` (bsdtar basename match) and `*/NAME` (GNU tar nested match) so the
# pruning is portable and applies at any depth. Used by both backup and the
# pre-restore snapshot.
ccb_tar_excludes() {
  [ "${OPT_FULL:-0}" = "1" ] && return 0
  local names="$CCB_EXCLUDE_NAMES" n
  [ "${OPT_NO_HISTORY:-0}" = "1" ] && names="$names projects"
  for n in $names; do
    printf -- '--exclude=%s\n' "$n"
    printf -- '--exclude=*/%s\n' "$n"
  done
}

# ---------------------------------------------------------------------------
# Backup directory resolution
# ---------------------------------------------------------------------------
# Override order: explicit --dest (passed as $1) > $CLAUDE_BACKUP_DIR > default.
resolve_backup_dir() {
  local explicit="${1:-}"
  if [ -n "$explicit" ]; then
    printf '%s\n' "$explicit"
  elif [ -n "${CLAUDE_BACKUP_DIR:-}" ]; then
    printf '%s\n' "$CLAUDE_BACKUP_DIR"
  else
    printf '%s\n' "$HOME/Backups/claude-code"
  fi
}

# ---------------------------------------------------------------------------
# Claude Code introspection (must never fail the caller)
# ---------------------------------------------------------------------------
# claude_version - print the Claude Code CLI version, or "not found".
claude_version() {
  if command -v claude >/dev/null 2>&1; then
    claude --version 2>/dev/null | head -n1 || printf 'unknown\n'
  else
    printf 'not found\n'
  fi
}

# ---------------------------------------------------------------------------
# Misc helpers
# ---------------------------------------------------------------------------
# confirm <prompt> - ask a yes/no question. Returns 0 for yes. Defaults to no.
# Returns non-zero (no) automatically when stdin is not a TTY.
confirm() {
  local prompt="$1" reply=""
  if [ ! -t 0 ]; then
    return 1
  fi
  printf '%s [y/N] ' "$prompt" >&2
  read -r reply || return 1
  case "$reply" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# require_cmd <cmd> - die if a required command is missing.
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}
