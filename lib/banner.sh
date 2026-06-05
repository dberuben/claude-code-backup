# shellcheck shell=bash
#
# banner.sh - Compact status line for shells and Claude Code.
#
# Renders a two-line banner describing the current project, environment and
# backup health. All detection degrades silently: missing git, missing kubectl
# and missing backups never produce errors, only sensible fallbacks.
#
# Sourced by bin/claude-backup-banner (which also sources restore.sh for
# latest_backup). Not run directly.

# load_banner_config - apply defaults then overlay the user's banner.conf.
load_banner_config() {
  BANNER_ENABLED="true"
  BANNER_SHOW_GIT="true"
  BANNER_SHOW_ENV="true"
  BANNER_SHOW_BACKUP_STATUS="true"
  BANNER_SHOW_MCP_STATUS="true"
  BANNER_SHOW_SECRET_WARNING="true"
  BANNER_STYLE="compact"
  BANNER_PROJECT_NAME_AUTO="true"
  BANNER_PROJECT_NAME=""
  BANNER_ENV_AUTO="true"
  BANNER_ENV=""
  BANNER_MAX_BACKUP_AGE_HOURS="24"

  local cfg="${CCB_BANNER_CONF:-$HOME/.claude-backup/banner.conf}"
  if [ -f "$cfg" ]; then
    # The config is a set of KEY=value lines owned by the user. Source it.
    # shellcheck disable=SC1090
    . "$cfg"
  fi
}

# banner_project_name - left-hand project label.
banner_project_name() {
  if [ "${BANNER_PROJECT_NAME_AUTO:-true}" != "true" ] && [ -n "${BANNER_PROJECT_NAME:-}" ]; then
    printf '%s\n' "$BANNER_PROJECT_NAME"
    return
  fi
  local root=""
  if command -v git >/dev/null 2>&1; then
    root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  if [ -n "$root" ]; then
    basename "$root"
  else
    basename "$PWD"
  fi
}

# banner_dir_label - right-hand label (current directory name).
banner_dir_label() { basename "$PWD"; }

# banner_git_branch - current branch, or empty.
banner_git_branch() {
  command -v git >/dev/null 2>&1 || return 0
  git rev-parse --abbrev-ref HEAD 2>/dev/null || true
}

# _env_from_string <s> - echo a known environment keyword found in a string.
_env_from_string() {
  case "$1" in
    *prod*)            printf 'prod' ;;
    *staging*|*stage*) printf 'stage' ;;
    *dev*)             printf 'dev' ;;
    *trial*)           printf 'trial' ;;
    *)                 printf '' ;;
  esac
}

# banner_environment - detect the environment per the documented precedence.
banner_environment() {
  if [ "${BANNER_ENV_AUTO:-true}" != "true" ] && [ -n "${BANNER_ENV:-}" ]; then
    printf '%s\n' "$BANNER_ENV"; return
  fi

  # Explicit environment variables win, in order.
  local v
  for v in "${CLAUDE_ENV:-}" "${ENV:-}" "${APP_ENV:-}" "${NODE_ENV:-}"; do
    if [ -n "$v" ]; then printf '%s\n' "$v"; return; fi
  done

  # Kubernetes context, only if kubectl exists (never required).
  if command -v kubectl >/dev/null 2>&1; then
    local kctx hit
    kctx="$(kubectl config current-context 2>/dev/null || true)"
    if [ -n "$kctx" ]; then
      hit="$(_env_from_string "$kctx")"
      if [ -n "$hit" ]; then printf '%s\n' "$hit"; return; fi
    fi
  fi

  # Git branch name, then current path.
  local branch hit
  branch="$(banner_git_branch)"
  hit="$(_env_from_string "$branch")"
  [ -n "$hit" ] && { printf '%s\n' "$hit"; return; }
  hit="$(_env_from_string "$PWD")"
  [ -n "$hit" ] && { printf '%s\n' "$hit"; return; }

  printf 'local\n'
}

# banner_backup_age_seconds - seconds since the latest backup, or empty.
banner_backup_age_seconds() {
  local dir latest mt
  dir="$(resolve_backup_dir "")"
  latest="$(latest_backup "$dir")"
  [ -n "$latest" ] || return 0
  mt="$(file_mtime "$latest")"
  [ -n "$mt" ] || return 0
  printf '%s\n' "$(( $(now_epoch) - mt ))"
}

# banner_mcp_status - "ok" when MCP config is present, "none" otherwise.
banner_mcp_status() {
  if [ -f "$PWD/.mcp.json" ] || [ -f "$HOME/.claude.json" ]; then
    printf 'ok\n'
  else
    printf 'none\n'
  fi
}

# banner_config_status - "check" if any sensitive config looks like it holds
# secrets, "ok" otherwise. Never prints any secret value.
banner_config_status() {
  [ "${BANNER_SHOW_SECRET_WARNING:-true}" = "true" ] || { printf 'ok\n'; return; }
  local f
  for f in "$PWD/.mcp.json" "$PWD/.claude/settings.local.json" "$HOME/.claude.json"; do
    if [ -f "$f" ] && scan_file "$f" >/dev/null 2>&1; then
      printf 'check\n'; return
    fi
  done
  printf 'ok\n'
}

# render_banner - print the two-line compact banner to stdout.
render_banner() {
  load_banner_config
  [ "${BANNER_ENABLED:-true}" = "true" ] || return 0

  local project dir branch env line1 glyph
  project="$(banner_project_name)"
  dir="$(banner_dir_label)"

  # --- Line 1: context ------------------------------------------------------
  line1="(⎈ ${project}"
  if [ "${BANNER_SHOW_ENV:-true}" = "true" ]; then
    env="$(banner_environment)"
    line1="${line1}|${env}"
  fi
  line1="${line1}) → ${dir}"
  if [ "${BANNER_SHOW_GIT:-true}" = "true" ]; then
    branch="$(banner_git_branch)"
    [ -n "$branch" ] && line1="${line1} (${branch})"
  fi

  # --- Line 2: status -------------------------------------------------------
  local parts=() age_s age_label backup_warn=0
  if [ "${BANNER_SHOW_BACKUP_STATUS:-true}" = "true" ]; then
    age_s="$(banner_backup_age_seconds)"
    if [ -z "$age_s" ]; then
      age_label="never"; backup_warn=1
    else
      age_label="$(human_age "$age_s") ago"
      local max_s=$(( ${BANNER_MAX_BACKUP_AGE_HOURS:-24} * 3600 ))
      [ "$age_s" -gt "$max_s" ] && backup_warn=1
    fi
    parts+=("backup: $age_label")
  fi
  if [ "${BANNER_SHOW_MCP_STATUS:-true}" = "true" ]; then
    parts+=("mcp: $(banner_mcp_status)")
  fi
  if [ "${BANNER_SHOW_SECRET_WARNING:-true}" = "true" ]; then
    parts+=("config: $(banner_config_status)")
  fi

  # Health glyph: warn when no/stale backup, otherwise the half-moon.
  if [ "$backup_warn" = "1" ]; then glyph="⚠"; else glyph="◐"; fi

  # Join status parts with " · " (${parts[@]+…} keeps an empty array safe on 3.2).
  local line2="" p
  for p in ${parts[@]+"${parts[@]}"}; do
    if [ -z "$line2" ]; then line2="$p"; else line2="$line2 · $p"; fi
  done

  printf '%s%s%s\n' "$C_DIM" "$line1" "$C_RESET"
  printf '%s %s\n' "$glyph" "$line2"
  return 0
}
