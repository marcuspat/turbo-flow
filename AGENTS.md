# AGENTS.md — Turbo Flow

Turbo Flow is **rig-lite**: a portable governance kit for AI-written code. Bash plus this file — no harness is bundled, no new dependencies. It works with whatever coding agents you already have.

> This file is the source of truth for every harness. `CLAUDE.md` is a symlink to it; Codex and ZCode read it natively. Do not fork instructions per tool.

## The one rule that matters

Every change is reviewed read-only by a model from a **different family** than the one that wrote it, and **humans hold the merge button**. Enforce it with the gate:

```bash
rig-lite/gate.sh --pr <n> --builder <cli>    # gate a GitHub PR, verdict posted as a comment
rig-lite/gate.sh --base main --builder <cli> # branch mode on a working tree
```

The full law set lives in [`rig-lite/constitution.md`](rig-lite/constitution.md) — pair it with the gate so the laws have teeth.

## Repo map

| Path | What it is |
|---|---|
| `rig-lite/` | the kit: gate, worktrees, secrets, digest, token dashboard, memory pattern, spec templates, automation prompts, self-test |
| `demo/` | the recorded demo + its recorder + auth-guard (refuses to record logged-in sessions) |
| `.devcontainer/` | minimal container whose postCreate runs the kit self-test — the 30-second tour |

## Working in this repo

- After any change: `bash rig-lite/self-test.sh` (fail-closed; says so when shellcheck-gated coverage is skipped)
- Secrets: never in git — `rig-lite/secret.sh set/get/rm/list` (names only when listing)
- Parallel writers: one worktree each — `rig-lite/wt.sh <name>`
- Durable facts: `rig-lite/memory/`, one fact per file, git-versioned
- Changes arrive by PR + gate. Builders never merge; humans do.

## Harnesses (by role, none bundled)

**ZCode builds · Claude Code reviews — with the Ruflo mod installed when you want orchestration · Codex backs up the review.**

The gate knows the builder families (`claude`, `codex`, `glm`/`zcode`/`zai`, `gemini`, `grok`, `xai`) and refuses to run unless it can find a reviewer from a family other than the builder's.
