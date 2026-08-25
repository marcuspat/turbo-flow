# CLAUDE.md — Turbo Flow

Turbo Flow is a shell-based dev environment bootstrapper for Claude Code + Ruflo.

## What This Repo Is

A setup wizard and collection of boot scripts for DevPods and GitHub Codespaces.
Installs Claude Code, Ruflo v3.5 plugins, MCP servers, and shell aliases.

## Key Files

- `devpods/setup.sh` — main bootstrapper
- `devpods/tf-verify.sh` — post-setup verification
- `devpods/scripts/` — platform-specific boot scripts
- `devpods/post-setup.sh` — post-install bootstrap (aliases, MCP)

## Conventions

- Commit messages: conventional commits
- Branch: main
- Shell scripts must pass `bash -n`
