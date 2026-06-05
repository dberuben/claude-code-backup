# shellcheck shell=bash
#
# archive.sh - Build the backup plan, staging directory, manifest and tarball.
#
# The orchestration entrypoint is do_backup(), which reads OPT_* globals set by
# bin/claude-backup. It is written so that a missing Claude Code install, a
# missing project config, or a missing iCloud directory degrade gracefully
# rather than aborting the backup.
#
# Sourced by bin/claude-backup. Do not run directly.

# Files collected for the archive, recorded as "absolute-source|archive-relpath".
CCB_PLAN_FILES=()
# Human-readable notes about plan entries that were absent (for the manifest).
CCB_SKIPPED=()

# build_stage <stage> - symlink each planned entry into the staging dir at its
# top-level archive path. No data is copied and the source trees are NOT walked
# here: pruning of large/ephemeral subdirs is done by tar --exclude during
# archiving (see ccb_tar_excludes / archive_with_progress), which matches names
# at any depth in a single pass. tar -h dereferences these symlinks.
build_stage() {
  local stage="$1" entry src rel
  for entry in "${CCB_PLAN_FILES[@]}"; do
    src="${entry%%|*}"; rel="${entry##*|}"
    mkdir -p "$stage/$(dirname "$rel")"
    ln -s "$src" "$stage/$rel"
  done
}

# ccb_tar_excludes - echo the tar --exclude flags (one per line) for the pruned
# names under the current options. Empty under --full. For each NAME we emit
# both `NAME` (bsdtar basename match) and `*/NAME` (GNU tar nested match) so the
# pruning is portable and applies at any depth.
ccb_tar_excludes() {
  [ "${OPT_FULL:-0}" = "1" ] && return 0
  local names="$CCB_EXCLUDE_NAMES" n
  [ "${OPT_NO_HISTORY:-0}" = "1" ] && names="$names projects"
  for n in $names; do
    printf -- '--exclude=%s\n' "$n"
    printf -- '--exclude=*/%s\n' "$n"
  done
}

# archive_with_progress <archive> <stage> <exclude-arg...> - tar+gzip the stage,
# dereferencing symlinks (-h) and applying the exclude args. Shows a live
# spinner with the growing archive size on a TTY; silent otherwise. Returns
# tar's exit status.
archive_with_progress() {
  local archive="$1" stage="$2"; shift 2
  # Remaining args ("$@") are the tar --exclude flags; there may be none (--full).
  # We use "$@" directly (safe when empty, even under bash 3.2 + set -u) rather
  # than an array, which would trip "unbound variable" on 3.2 when empty.
  if [ ! -t 2 ] || [ "${CCB_QUIET:-0}" = "1" ] || [ "${CCB_JSON:-0}" = "1" ]; then
    tar -czhf "$archive" -C "$stage" "$@" .
    return $?
  fi
  local frames=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
  local i=0 start sz el rc pid
  start="$(now_epoch)"
  tar -czhf "$archive" -C "$stage" "$@" . &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sz="$(human_size "$(file_size "$archive" 2>/dev/null || echo 0)")"
    el="$(( $(now_epoch) - start ))"
    printf '\r  %s  archiving… %s  (%ds)   ' "${frames[i % ${#frames[@]}]}" "$sz" "$el" >&2
    i=$((i + 1))
    sleep 1
  done
  if wait "$pid"; then rc=0; else rc=$?; fi
  printf '\r%60s\r' '' >&2   # clear the spinner line
  return "$rc"
}

# _plan_add <source> <archive-relpath> - add an existing path to the plan, or
# record it as skipped when it does not exist.
_plan_add() {
  local src="$1" rel="$2"
  if [ -e "$src" ]; then
    CCB_PLAN_FILES+=("$src|$rel")
  else
    CCB_SKIPPED+=("$rel (not present)")
  fi
}

# build_plan - populate CCB_PLAN_FILES / CCB_SKIPPED from the current options.
build_plan() {
  CCB_PLAN_FILES=()
  CCB_SKIPPED=()

  # --- Global (home) config -------------------------------------------------
  _plan_add "$HOME/.claude"      "home/.claude"
  _plan_add "$HOME/.claude.json" "home/.claude.json"

  # --- Project config (current working directory) ---------------------------
  if [ "${OPT_INCLUDE_PROJECT:-1}" = "1" ]; then
    _plan_add "$PWD/.claude"          "project/.claude"
    _plan_add "$PWD/.mcp.json"        "project/.mcp.json"
    _plan_add "$PWD/CLAUDE.md"        "project/CLAUDE.md"
    _plan_add "$PWD/CLAUDE.local.md"  "project/CLAUDE.local.md"

    # Environment files may hold secrets; only include with --include-env.
    if [ "${OPT_INCLUDE_ENV:-0}" = "1" ]; then
      _plan_add "$PWD/.env.claude" "project/.env.claude"
      _plan_add "$PWD/.envrc"      "project/.envrc"
    else
      [ -e "$PWD/.env.claude" ] && CCB_SKIPPED+=(".env.claude (use --include-env)") || true
      [ -e "$PWD/.envrc" ]      && CCB_SKIPPED+=(".envrc (use --include-env)")      || true
    fi
  else
    CCB_SKIPPED+=("project config (--no-project)")
  fi
  return 0  # never let a trailing test's exit status trip `set -e`
}

# git_info - print "repo-path|branch" for the current directory, empty fields
# when not inside a git repository.
git_info() {
  local root="" branch=""
  if command -v git >/dev/null 2>&1; then
    root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$root" ]; then
      branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    fi
  fi
  printf '%s|%s\n' "$root" "$branch"
}

# write_manifest <path> <warnings> - generate the manifest file.
write_manifest() {
  local out="$1" warnings="$2" gi git_root git_branch entry
  gi="$(git_info)"; git_root="${gi%%|*}"; git_branch="${gi##*|}"

  {
    printf 'claude-code-backup manifest\n'
    printf '===========================\n'
    printf 'backup_tool_version: %s\n' "$CCB_VERSION"
    printf 'timestamp_utc:       %s\n' "$(utc_timestamp)"
    printf 'timestamp_local:     %s\n' "$(date +"%Y-%m-%d %H:%M:%S %Z")"
    printf 'hostname:            %s\n' "$(hostname 2>/dev/null || echo unknown)"
    printf 'username:            %s\n' "$(id -un 2>/dev/null || echo "${USER:-unknown}")"
    printf 'platform:            %s\n' "${CCB_PLATFORM:-unknown}"
    printf 'os_version:          %s\n' "$(os_version)"
    printf 'shell:               %s\n' "${SHELL:-unknown}"
    printf 'claude_code_version: %s\n' "$(claude_version)"
    printf 'git_repository:      %s\n' "${git_root:-not in a git repo}"
    printf 'git_branch:          %s\n' "${git_branch:-n/a}"
    printf 'working_directory:   %s\n' "$PWD"
    printf '\nincluded_files:\n'
    for entry in "${CCB_PLAN_FILES[@]}"; do
      printf '  - %s\n' "${entry##*|}"
    done
    printf '\nskipped_files:\n'
    if [ "${#CCB_SKIPPED[@]}" -eq 0 ]; then
      printf '  (none)\n'
    else
      for entry in "${CCB_SKIPPED[@]}"; do
        printf '  - %s\n' "$entry"
      done
    fi
    printf '\npruned (large/ephemeral dir names, not backed up):\n'
    if [ "${OPT_FULL:-0}" = "1" ]; then
      printf '  (none — --full)\n'
    else
      printf '  %s\n' "$CCB_EXCLUDE_NAMES"
      [ "${OPT_NO_HISTORY:-0}" = "1" ] && printf '  projects (--no-history)\n'
      printf '  (use --full to include everything)\n'
    fi
    printf '\nwarnings:\n'
    if [ -z "$warnings" ]; then
      printf '  (none)\n'
    else
      printf '%s\n' "$warnings" | sed 's/^/  - /'
    fi
  } >"$out"
}

# do_backup - main backup routine. Reads OPT_* globals. Prints the archive path
# on stdout (or a JSON object with --json). Returns 0 on success.
do_backup() {
  require_cmd tar
  require_cmd gzip

  local backup_dir; backup_dir="$(resolve_backup_dir "${OPT_DEST:-}")"
  build_plan

  # Fail clearly (not with an "unbound variable") when there is nothing to back
  # up; also keeps every "${CCB_PLAN_FILES[@]}" loop below non-empty on bash 3.2.
  [ "${#CCB_PLAN_FILES[@]}" -gt 0 ] || \
    die "nothing to back up: no Claude config found (~/.claude, ~/.claude.json, or project files)"

  # --- Secret scan ----------------------------------------------------------
  local secret_hits="" warnings=""
  [ "$CCB_JSON" = "1" ] || log_step "Scanning for secrets…"
  secret_hits="$(scan_plan_for_secrets || true)"
  if [ -n "$secret_hits" ]; then
    warnings="archive may contain secrets (see scanned files below)"
    if [ "$CCB_JSON" != "1" ]; then
      if [ "${CCB_QUIET:-0}" = "1" ]; then
        # Minimal: one line, no per-file list.
        log_warn "Potential secrets detected ($(printf '%s\n' "$secret_hits" | grep -c .) files); see 'claude-backup doctor'."
      else
        log_warn "Potential secrets detected in files queued for backup:"
        printf '%s\n' "$secret_hits" | summarize_secret_hits >&2
        log_warn "Backups may contain Claude credentials, MCP tokens, OAuth state,"
        log_warn "API keys, local paths and private project instructions."
        log_warn "NEVER commit backups to git. Store them in encrypted storage."
      fi
    fi
    if [ "${OPT_STRICT:-0}" = "1" ]; then
      die "strict-secrets: aborting because likely secrets were detected"
    fi
  fi

  # --- Build the staging tree (top-level symlinks only) ---------------------
  local stage; stage="$(mktemp -d "${TMPDIR:-/tmp}/ccb-stage.XXXXXX")" \
    || die "cannot create temporary staging directory"
  # shellcheck disable=SC2317
  _cleanup_stage() { rm -rf "$stage"; }
  trap _cleanup_stage EXIT
  build_stage "$stage"

  # tar --exclude flags that prune large/ephemeral subdirs at any depth.
  local excludes=() line
  while IFS= read -r line; do [ -n "$line" ] && excludes+=("$line"); done < <(ccb_tar_excludes)

  # --- Dry run --------------------------------------------------------------
  if [ "${OPT_DRY_RUN:-0}" = "1" ]; then
    print_backup_plan "$backup_dir" "$secret_hits"
    _cleanup_stage; trap - EXIT
    return 0
  fi

  # --- Archive --------------------------------------------------------------
  mkdir -p "$backup_dir" || die "cannot create backup directory: $backup_dir"
  [ -w "$backup_dir" ] || die "backup directory not writable: $backup_dir"

  write_manifest "$stage/manifest.txt" "$warnings"

  local stamp host archive
  stamp="$(local_timestamp)"
  host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo host)"
  archive="$backup_dir/claude-code-backup-${stamp}_${host}.tar.gz"

  # -h dereferences the staged symlinks so real file contents are archived;
  # -C makes paths relative (home/…, project/…, manifest.txt) with no absolute
  # or parent components.
  # ${excludes[@]+...} so an empty array (under --full) is safe on bash 3.2.
  archive_with_progress "$archive" "$stage" ${excludes[@]+"${excludes[@]}"} || die "tar failed"

  _cleanup_stage
  trap - EXIT

  # --- iCloud copy (macOS only) ---------------------------------------------
  local icloud_copy=""
  if [ "${OPT_ICLOUD:-0}" = "1" ]; then
    icloud_copy="$(copy_to_icloud "$archive" || true)"
  fi

  if [ "$CCB_JSON" = "1" ]; then
    emit_backup_json "$archive" "$icloud_copy" "$secret_hits"
  else
    log_ok "Backup created: $archive ($(human_size "$(file_size "$archive")"))"
    [ "${#excludes[@]}" -gt 0 ] && \
      log_info "  pruned large/ephemeral dirs (caches, plugin code, venvs…); use --full to keep them"
    [ -n "$icloud_copy" ] && log_ok "Copied to iCloud: $icloud_copy"
    printf '%s\n' "$archive"
  fi
  return 0
}

# scan_plan_for_secrets - run the secret scanner over every planned source path.
scan_plan_for_secrets() {
  local entry srcs=()
  for entry in "${CCB_PLAN_FILES[@]}"; do
    srcs+=("${entry%%|*}")
  done
  [ "${#srcs[@]}" -gt 0 ] || return 1
  scan_paths "${srcs[@]}"
}

# copy_to_icloud <archive> - copy the archive into iCloud Drive on macOS.
# Prints the destination path on success; warns and returns non-zero otherwise.
copy_to_icloud() {
  local archive="$1" dir dest
  if [ "${CCB_PLATFORM:-}" != "macos" ]; then
    log_warn "--icloud ignored: not running on macOS"
    return 1
  fi
  if ! dir="$(icloud_dir)"; then
    log_warn "--icloud ignored: iCloud Drive directory not found"
    return 1
  fi
  dest="$dir/claude-code-backup"
  mkdir -p "$dest" || { log_warn "cannot create iCloud folder"; return 1; }
  cp -p "$archive" "$dest/" || { log_warn "iCloud copy failed"; return 1; }
  printf '%s/%s\n' "$dest" "$(basename "$archive")"
}

# print_backup_plan <backup_dir> <secret_hits> - human/JSON dry-run output.
print_backup_plan() {
  local backup_dir="$1" secret_hits="$2" entry
  if [ "$CCB_JSON" = "1" ]; then
    emit_plan_json "$backup_dir" "$secret_hits"
    return 0
  fi
  log_step "Dry run - no archive will be written"
  log_info "Destination: $backup_dir"
  log_info "Would include:"
  for entry in "${CCB_PLAN_FILES[@]}"; do
    log_info "  + ${entry##*|}"
  done
  if [ "${#CCB_SKIPPED[@]}" -gt 0 ]; then
    log_info "Would skip (absent):"
    for entry in "${CCB_SKIPPED[@]}"; do
      log_info "  - $entry"
    done
  fi
  if [ "${OPT_FULL:-0}" != "1" ]; then
    log_info "Would prune these dir names at any depth: $CCB_EXCLUDE_NAMES"
    [ "${OPT_NO_HISTORY:-0}" = "1" ] && log_info "  and projects/ (--no-history)"
    log_info "  (--full keeps everything)"
  fi
  [ -n "$secret_hits" ] && log_warn "Potential secrets detected (see 'doctor' for details)"
  return 0
}

# emit_backup_json <archive> <icloud> <secret_hits>
emit_backup_json() {
  local archive="$1" icloud="$2" secret_hits="$3" has_secrets="false"
  [ -n "$secret_hits" ] && has_secrets="true"
  printf '{"status":"ok","archive":"%s","size_bytes":%s,"icloud_copy":"%s","secrets_detected":%s,"version":"%s"}\n' \
    "$(json_escape "$archive")" \
    "$(file_size "$archive")" \
    "$(json_escape "$icloud")" \
    "$has_secrets" \
    "$CCB_VERSION"
}

# emit_plan_json <backup_dir> <secret_hits>
emit_plan_json() {
  local backup_dir="$1" secret_hits="$2" has_secrets="false" entry first=1
  [ -n "$secret_hits" ] && has_secrets="true"
  printf '{"status":"dry-run","destination":"%s","included":[' "$(json_escape "$backup_dir")"
  for entry in "${CCB_PLAN_FILES[@]}"; do
    [ "$first" = "1" ] || printf ','
    printf '"%s"' "$(json_escape "${entry##*|}")"
    first=0
  done
  printf '],"skipped":['
  first=1
  for entry in "${CCB_SKIPPED[@]}"; do
    [ "$first" = "1" ] || printf ','
    printf '"%s"' "$(json_escape "$entry")"
    first=0
  done
  printf '],"secrets_detected":%s,"version":"%s"}\n' "$has_secrets" "$CCB_VERSION"
}
