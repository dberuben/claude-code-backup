# shellcheck shell=bash
#
# restore.sh - List backups and safely restore them.
#
# SAFETY IS THE PRIORITY HERE. The restore path must, in order:
#   1. validate the archive's entry list (no absolute paths, no "..")
#   2. extract to a temporary directory (never straight into $HOME)
#   3. reject symlinks that escape the extraction directory
#   4. show a plan and require confirmation unless --force
#   5. take a pre-restore backup of anything it is about to overwrite
#   6. copy files into place by MERGING (never blindly deleting user files)
#
# Sourced by bin/claude-restore (and bin/claude-backup for `list`). Not run
# directly.

# ---------------------------------------------------------------------------
# Listing
# ---------------------------------------------------------------------------
# list_backups <dir> - print "epoch<TAB>path" for each backup, newest first.
_enumerate_backups() {
  local dir="$1" f mt
  [ -d "$dir" ] || return 0
  while IFS= read -r -d '' f; do
    mt="$(file_mtime "$f")"
    [ -n "$mt" ] && printf '%s\t%s\n' "$mt" "$f"
  done < <(find "$dir" -maxdepth 1 -type f -name 'claude-code-backup-*.tar.gz' -print0 2>/dev/null) \
    | sort -rn
}

# latest_backup <dir> - print the path of the most recent backup, or nothing.
latest_backup() {
  _enumerate_backups "$1" | head -n1 | cut -f2-
}

# do_list - implements `claude-backup list` and `claude-restore --list`.
# Reads OPT_DEST for an optional directory override.
do_list() {
  local dir line mt path now size age first=1
  dir="$(resolve_backup_dir "${OPT_DEST:-}")"
  now="$(now_epoch)"

  if [ "$CCB_JSON" = "1" ]; then
    printf '{"directory":"%s","backups":[' "$(json_escape "$dir")"
    while IFS=$'\t' read -r mt path; do
      [ -n "$path" ] || continue
      size="$(file_size "$path")"
      age="$((now - mt))"
      [ "$first" = "1" ] || printf ','
      printf '{"name":"%s","path":"%s","size_bytes":%s,"age_seconds":%s}' \
        "$(json_escape "$(basename "$path")")" "$(json_escape "$path")" "${size:-0}" "$age"
      first=0
    done < <(_enumerate_backups "$dir")
    printf ']}\n'
    return 0
  fi

  log_step "Backups in $dir"
  if [ ! -d "$dir" ] || [ -z "$(_enumerate_backups "$dir")" ]; then
    log_info "  (no backups found)"
    return 0
  fi
  while IFS=$'\t' read -r mt path; do
    [ -n "$path" ] || continue
    size="$(human_size "$(file_size "$path")")"
    age="$(human_age "$((now - mt))")"
    printf '  %-52s %6s  %s ago\n' "$(basename "$path")" "$size" "$age" >&2
    printf '      %s\n' "$path" >&2
  done < <(_enumerate_backups "$dir")
  return 0
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
# validate_archive_listing <archive> - inspect the tar listing for unsafe paths.
# Rejects absolute paths and any ".." path component. Returns non-zero on danger.
validate_archive_listing() {
  local archive="$1" entry clean
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    # Normalise a leading "./" which tar adds for relative archives.
    clean="${entry#./}"
    case "$clean" in
      /*)        log_err "unsafe absolute path in archive: $entry"; return 1 ;;
      ..|../*|*/../*|*/..) log_err "unsafe parent path in archive: $entry"; return 1 ;;
    esac
    # Only manifest.txt, home/ and project/ trees are expected.
    case "$clean" in
      ""|.|manifest.txt|home|home/*|project|project/*) ;;
      *) log_warn "unexpected entry in archive (ignored on restore): $entry" ;;
    esac
  done < <(tar -tzf "$archive" 2>/dev/null)
}

# validate_extracted_tree <dir> - reject symlinks whose target escapes <dir>.
# Comments here are deliberate: this is the guard against symlink-escape attacks.
validate_extracted_tree() {
  local dir="$1" link target
  while IFS= read -r -d '' link; do
    target="$(readlink "$link" 2>/dev/null || true)"
    # An absolute target, or one that walks up with "..", could point outside
    # the staging directory and let a restore write to an arbitrary location.
    case "$target" in
      /*|*..*)
        log_err "archive contains an escaping symlink (rejected): $link -> $target"
        return 1
        ;;
    esac
  done < <(find "$dir" -type l -print0 2>/dev/null)
  return 0
}

# ---------------------------------------------------------------------------
# Pre-restore backup
# ---------------------------------------------------------------------------
# create_pre_restore_backup - tar up whatever currently exists among the restore
# targets so the user can roll back. Stored under .../pre-restore/.
create_pre_restore_backup() {
  local base dir stage stamp host archive targets=()
  base="$(resolve_backup_dir "${OPT_DEST:-}")"
  dir="$base/pre-restore"

  # Collect existing targets relevant to the current restore scope.
  if [ "${OPT_PROJECT_ONLY:-0}" != "1" ]; then
    [ -e "$HOME/.claude" ]      && targets+=("$HOME/.claude")
    [ -e "$HOME/.claude.json" ] && targets+=("$HOME/.claude.json")
  fi
  if [ "${OPT_HOME_ONLY:-0}" != "1" ]; then
    [ -e "$PWD/.claude" ]         && targets+=("$PWD/.claude")
    [ -e "$PWD/.mcp.json" ]       && targets+=("$PWD/.mcp.json")
    [ -e "$PWD/CLAUDE.md" ]       && targets+=("$PWD/CLAUDE.md")
    [ -e "$PWD/CLAUDE.local.md" ] && targets+=("$PWD/CLAUDE.local.md")
  fi

  if [ "${#targets[@]}" -eq 0 ]; then
    log_info "No existing config to back up before restore."
    return 0
  fi

  mkdir -p "$dir" || { log_warn "cannot create pre-restore dir: $dir"; return 1; }
  stage="$(mktemp -d "${TMPDIR:-/tmp}/ccb-prerestore.XXXXXX")" || return 1

  # Symlink the targets into the staging dir (no data copy) and let `tar -czh`
  # dereference them, pruning the same large/ephemeral dirs as a normal backup.
  # This avoids copying a multi-GB ~/.claude to a temp dir just to snapshot it.
  local t name
  for t in "${targets[@]}"; do
    case "$t" in
      "$HOME"/*) name="home/${t#"$HOME"/}" ;;
      *)         name="project/$(basename "$t")" ;;
    esac
    mkdir -p "$stage/$(dirname "$name")"
    ln -s "$t" "$stage/$name"
  done

  local excludes=() line
  while IFS= read -r line; do [ -n "$line" ] && excludes+=("$line"); done < <(ccb_tar_excludes)

  stamp="$(local_timestamp)"
  host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo host)"
  archive="$dir/pre-restore-${stamp}_${host}.tar.gz"
  # ${excludes[@]+...} keeps an empty array safe under bash 3.2.
  if tar -czhf "$archive" -C "$stage" ${excludes[@]+"${excludes[@]}"} .; then
    log_ok "Pre-restore backup: $archive"
  else
    rm -f "$archive" 2>/dev/null || true
    log_warn "pre-restore tar failed"
    rm -rf "$stage"
    return 1
  fi
  rm -rf "$stage"
}

# ---------------------------------------------------------------------------
# Restore
# ---------------------------------------------------------------------------
# _merge_copy <src> <dest> - copy src into dest by merging. For directories we
# copy the *contents* so files already in dest that are absent from the backup
# are preserved (we never silently delete user data).
_merge_copy() {
  local src="$1" dest="$2"
  if [ -d "$src" ]; then
    mkdir -p "$dest"
    # The "/." suffix copies directory contents, merging into dest.
    cp -R "$src/." "$dest/"
  else
    mkdir -p "$(dirname "$dest")"
    cp -p "$src" "$dest"
  fi
}

# claude_is_running - best-effort check for a live Claude Code process. Uses
# pgrep when present (macOS + Linux); skips silently otherwise. Restoring under
# a running Claude Code is risky: it rewrites ~/.claude.json continuously and
# may clobber the restore or not see it until restart.
claude_is_running() {
  command -v pgrep >/dev/null 2>&1 || return 1
  pgrep -x claude >/dev/null 2>&1
}

# do_restore - main restore routine. Reads OPT_* globals.
do_restore() {
  require_cmd tar

  # --- Select archive -------------------------------------------------------
  local archive="${OPT_FROM:-}"
  if [ -z "$archive" ]; then
    archive="$(latest_backup "$(resolve_backup_dir "${OPT_DEST:-}")")"
    [ -n "$archive" ] || die "no backup found; use --from <archive> or run 'claude-backup' first"
    log_info "Selected latest backup: $archive"
  fi
  [ -f "$archive" ] || die "archive not found: $archive"

  # --- Validate listing -----------------------------------------------------
  validate_archive_listing "$archive" || die "refusing to restore an unsafe archive"

  # --- Extract to temp ------------------------------------------------------
  local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/ccb-restore.XXXXXX")" \
    || die "cannot create temporary restore directory"
  # shellcheck disable=SC2317
  _cleanup_restore() { rm -rf "$tmp"; }
  trap _cleanup_restore EXIT

  tar -xzf "$archive" -C "$tmp" || die "failed to extract archive"
  validate_extracted_tree "$tmp" || die "refusing to restore: unsafe extracted tree"

  # --- Build the plan -------------------------------------------------------
  local do_home=1 do_project=1
  [ "${OPT_PROJECT_ONLY:-0}" = "1" ] && do_home=0
  [ "${OPT_HOME_ONLY:-0}" = "1" ]    && do_project=0

  local plan=()  # "src|dest"
  if [ "$do_home" = "1" ] && [ -d "$tmp/home" ]; then
    [ -e "$tmp/home/.claude" ]      && plan+=("$tmp/home/.claude|$HOME/.claude")
    [ -e "$tmp/home/.claude.json" ] && plan+=("$tmp/home/.claude.json|$HOME/.claude.json")
  fi
  if [ "$do_project" = "1" ] && [ -d "$tmp/project" ]; then
    local pf
    for pf in .claude .mcp.json CLAUDE.md CLAUDE.local.md .env.claude .envrc; do
      [ -e "$tmp/project/$pf" ] && plan+=("$tmp/project/$pf|$PWD/$pf")
    done
  fi

  [ "${#plan[@]}" -gt 0 ] || die "nothing to restore for the selected scope"

  # --- Show the plan --------------------------------------------------------
  local entry src dest
  if [ "$CCB_JSON" = "1" ] && [ "${OPT_DRY_RUN:-0}" = "1" ]; then
    emit_restore_plan_json "$archive" "${plan[@]}"
    _cleanup_restore; trap - EXIT
    return 0
  fi

  log_step "Restore plan (from $(basename "$archive"))"
  for entry in "${plan[@]}"; do
    src="${entry%%|*}"; dest="${entry##*|}"
    if [ ! -e "$dest" ]; then
      log_info "  create:        $dest"
    elif [ -d "$src" ]; then
      # Directory: backup contents are merged in; local-only files are kept.
      log_info "  merge into:    $dest"
    else
      # Single file: fully replaced by the backup's version (a revert).
      log_info "  overwrite:     $dest"
    fi
  done

  # Restoring under a running Claude Code can be clobbered or ignored until it
  # restarts; warn so the user can quit it first.
  if claude_is_running; then
    log_warn "Claude Code appears to be RUNNING."
    log_warn "  Quit it before restoring, otherwise it may overwrite ~/.claude.json"
    log_warn "  with its in-memory state, and changes may not apply until restart."
  fi

  if [ "${OPT_DRY_RUN:-0}" = "1" ]; then
    log_info "Dry run - no files were changed."
    _cleanup_restore; trap - EXIT
    return 0
  fi

  # --- Confirm --------------------------------------------------------------
  if [ "${OPT_FORCE:-0}" != "1" ]; then
    if ! confirm "Proceed with restore? Existing files will be merged/overwritten."; then
      log_info "Restore cancelled."
      _cleanup_restore; trap - EXIT
      return 1
    fi
  fi

  # --- Pre-restore backup ---------------------------------------------------
  if [ "${OPT_BACKUP_EXISTING:-1}" = "1" ]; then
    create_pre_restore_backup || log_warn "pre-restore backup failed; continuing"
  fi

  # --- Apply ----------------------------------------------------------------
  for entry in "${plan[@]}"; do
    src="${entry%%|*}"; dest="${entry##*|}"
    _merge_copy "$src" "$dest"
    log_ok "restored: $dest"
  done

  _cleanup_restore
  trap - EXIT

  # --- Post-restore guidance ------------------------------------------------
  if [ "$CCB_JSON" = "1" ]; then
    printf '{"status":"ok","restored_from":"%s","items":%s,"version":"%s"}\n' \
      "$(json_escape "$archive")" "${#plan[@]}" "$CCB_VERSION"
  else
    log_ok "Restore complete."
    log_info "Next steps:"
    log_info "  • If Claude Code was open, restart it to pick up the restored config."
    log_info "  • Plugin code is not part of a backup — reinstall from the restored"
    log_info "    manifest: see ~/.claude/plugins/installed_plugins.json, then"
    log_info "    /plugin marketplace add … and /plugin install … (or /reload-plugins)."
    log_warn "Some credentials may need re-authentication: OAuth tokens, Keychain"
    log_warn "entries, OS credential stores, and values held in external files or"
    log_warn "environment variables are NOT guaranteed to be restored. If Claude"
    log_warn "Code or an MCP server reports an auth error, re-login to refresh them."
  fi
}

# emit_restore_plan_json <archive> <plan...>
emit_restore_plan_json() {
  local archive="$1"; shift
  local entry first=1
  printf '{"status":"dry-run","archive":"%s","plan":[' "$(json_escape "$archive")"
  for entry in "$@"; do
    [ "$first" = "1" ] || printf ','
    printf '{"source":"%s","dest":"%s"}' \
      "$(json_escape "${entry%%|*}")" "$(json_escape "${entry##*|}")"
    first=0
  done
  printf '],"version":"%s"}\n' "$CCB_VERSION"
}
