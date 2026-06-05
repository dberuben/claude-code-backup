# Security Policy

## Backups can contain secrets

A `claude-code-backup` archive is a faithful copy of your Claude Code
configuration. That configuration commonly contains sensitive material:

- Claude credentials and session/OAuth state
- MCP server tokens and connection strings
- API keys (e.g. `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`)
- `authorization` / `bearer` headers stored in MCP configs
- local filesystem paths that reveal your directory layout
- project **trust** settings
- private project instructions (`CLAUDE.md`, `CLAUDE.local.md`)
- environment references (only when you pass `--include-env`)

**Treat every backup archive as if it contains live credentials.**

## Do not publish backups

- **Never commit backups to git.** The repository's `.gitignore` already
  excludes `*.tar.gz`, `Backups/`, `backups/`, `pre-restore/`, `.env*` and
  `banner.conf`, but you are responsible for where you write archives.
- Do not attach archives to issues, pastebins, chat messages or screenshots.
- Do not upload them to shared/unencrypted cloud folders.

## Recommended storage

- Keep archives on encrypted storage: FileVault (macOS), LUKS/dm-crypt
  (Linux), or an encrypted external volume.
- For portability, encrypt the archive itself before moving it, e.g.:

  ```bash
  # symmetric encryption with GnuPG (you will be prompted for a passphrase)
  gpg --symmetric --cipher-algo AES256 claude-code-backup-*.tar.gz
  # decrypt later:
  gpg --decrypt claude-code-backup-XXXX.tar.gz.gpg > restore.tar.gz
  ```

- If you place backups in a synced/cloud folder (Dropbox, Nextcloud, a network
  share…), remember the archive — which may contain secrets — is then copied to
  that service and every device attached to it. Prefer a local, encrypted
  location, or encrypt the archive first.

## The built-in secret scanner

`claude-code-backup` ships a **heuristic** scanner (`lib/security.sh`) that
flags files whose contents match patterns such as `sk-`, `api_key`, `token`,
`authorization`, `bearer`, `secret`, `password`, `github_pat`,
`ANTHROPIC_API_KEY` and `OPENAI_API_KEY`.

- By default it only **warns** — it never blocks a backup and never prints the
  matched value, only the file path and which pattern matched.
- Pass `--strict-secrets` to **abort** the backup when likely secrets are found.
- It is best-effort: it will miss novel token formats and will sometimes flag
  harmless text (false positives). Do not rely on it as your only safeguard.

## What this tool does NOT protect against

- It does not encrypt archives for you (see "Recommended storage").
- It does not redact secrets from your config; it copies files verbatim.
- It cannot restore credentials held **outside** the backed-up files — OS
  keychains/credential stores, OAuth tokens kept by external helpers, or values
  living only in environment variables. After a restore you may need to
  re-authenticate Claude Code or individual MCP servers.
- It performs **no network calls**, **no uploads**, **no telemetry** and **no
  auto-update**. Moving archives anywhere is entirely your decision.

## Responsible disclosure

If you discover a security issue in this tool (for example a path-traversal or
symlink-escape bypass in the restore logic), please report it privately:

1. Open a GitHub **security advisory** on the repository
   (`Security` tab → `Report a vulnerability`), or
2. email the maintainers listed in the repository metadata.

Please do **not** open a public issue for an unpatched vulnerability. We aim to
acknowledge reports within a few days and will credit reporters who wish to be
named.
