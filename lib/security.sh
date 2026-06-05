# shellcheck shell=bash
#
# security.sh - Lightweight secret detection.
#
# The scanner is intentionally heuristic: it flags files that *look like* they
# might contain credentials so the user can make an informed decision. It never
# prints the matched secret value, only the file path.
#
# Performance note: Claude config trees can be huge (100k+ files). The scanner
# therefore uses a SINGLE recursive grep (one process) with --exclude-dir for
# the ephemeral directories listed in CCB_EXCLUDE_NAMES, instead of spawning a
# grep per file per pattern.
#
# Sourced by common.sh. Do not run directly.

# Extended-regex alternation used with `grep -iE`. Tightened to cut false
# positives: rather than matching bare words like "token" or "secret" (which
# appear in prose, docs and SKILL.md everywhere), we match either
#   (a) high-confidence credential *formats* (provider key prefixes, JWTs,
#       PEM private-key headers, AWS access-key ids), or
#   (b) a credential-ish key immediately ASSIGNED a value of real length,
#       e.g. `api_key = "abcd...."`, `"token": "xoxb-..."`, `PASSWORD=hunter2longvalue`.
# It still never prints the matched text — only the file path.
CCB_SECRET_RE='(sk-(ant-)?[A-Za-z0-9_-]{16,})|(github_pat_[A-Za-z0-9_]{20,})|(gh[opsur]_[A-Za-z0-9]{20,})|(xox[baprs]-[A-Za-z0-9-]{10,})|(AKIA[0-9A-Z]{16})|(-----BEGIN [A-Z ]*PRIVATE KEY-----)|(eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+)|((api[_-]?key|secret([_-]?key)?|client[_-]?secret|access[_-]?key|auth[_-]?token|access[_-]?token|password|passwd|bearer|authorization)[[:space:]":=]{1,4}[A-Za-z0-9_./+=-]{12,})'

# _grep_exclude_args - echo the --exclude-dir flags for the ephemeral dirs so
# the scanner skips the same trees the backup prunes.
_grep_exclude_args() {
  local n
  # The scanner always skips these big trees (even under --full): scanning
  # gigabytes of plugin code and conversation transcripts is slow and noisy.
  for n in ${CCB_EXCLUDE_NAMES:-} projects; do
    printf -- '--exclude-dir=%s\n' "$n"
  done
}

# scan_file <path> - return 0 if the file looks like it contains a secret.
# Skips binary files. Never prints anything.
scan_file() {
  local path="$1"
  [ -f "$path" ] || return 1
  grep -I -q -i -E -e "$CCB_SECRET_RE" "$path" 2>/dev/null
}

# scan_paths <path...> - print the paths of files that look like they contain
# secrets, one per line. Uses a single recursive grep. Returns 0 if any match.
scan_paths() {
  [ "$#" -gt 0 ] || return 1
  local out exargs=()
  while IFS= read -r line; do [ -n "$line" ] && exargs+=("$line"); done < <(_grep_exclude_args)
  # -r recurse, -I skip binary, -l list filenames only (never the match text),
  # -i case-insensitive, -E extended regex. One process for the whole tree.
  out="$(grep -r -I -l -i -E ${exargs[@]+"${exargs[@]}"} -e "$CCB_SECRET_RE" "$@" 2>/dev/null)"
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
  return 0
}

# summarize_secret_hits - read file paths on stdin and print them indented.
# Never prints any secret value.
summarize_secret_hits() {
  sed 's/^/  /'
}
