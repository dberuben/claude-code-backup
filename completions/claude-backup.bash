# bash completion for claude-code-backup
# Install: source this file, or place it at
#   <prefix>/share/bash-completion/completions/claude-backup
#
# shellcheck disable=SC2207  # compgen word-splitting is the standard completion idiom

_claude_backup() {
  local cur prev words cword
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  local subcommands="list doctor banner"
  local opts="--dest --include-project --no-project --no-history --full --include-env \
    --strict-secrets --dry-run --json --quiet --help --version"

  # Complete a directory after --dest.
  if [ "$prev" = "--dest" ]; then
    COMPREPLY=( $(compgen -d -- "$cur") )
    return 0
  fi

  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "$subcommands $opts" -- "$cur") )
  else
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
  fi
}
complete -F _claude_backup claude-backup

_claude_restore() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  local opts="--from --list --dry-run --force --home-only --project-only \
    --backup-existing --no-backup-existing --dest --json --help --version"
  if [ "$prev" = "--from" ]; then
    COMPREPLY=( $(compgen -f -- "$cur") )
    return 0
  fi
  COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
}
complete -F _claude_restore claude-restore
