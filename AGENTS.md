# AGENTS.md — Turbo Flow

Turbo Flow is **rig-lite**: a portable governance kit for AI-written code. Bash plus this file — no harness is bundled, no new dependencies. It works with whatever coding agents you already have.

> This file is the source of truth for every harness. `CLAUDE.md` is a symlink to it; Codex and ZCode read it natively. Do not fork instructions per tool.

## The one rule that matters

Every change is reviewed read-only by a model from a **different family** than the one that wrote it, and **humans hold the merge button**. Enforce it with the gate:

```bash
rig-lite/gate.sh --pr <n> --builder <cli>    # gate a GitHub PR, verdict posted as a comment
# verdicts are pinned to the head they gated — new commits = ungated again.
# past GATE_ROUND_CAP (default 3) rounds the gate exits 4: the continue/park
# fork is the human's call (GATE_FORCE=1 overrides consciously).
rig-lite/gate.sh --base main --builder <cli> # branch mode on a working tree
```

The full law set lives in [`rig-lite/constitution.md`](rig-lite/constitution.md) — pair it with the gate so the laws have teeth.

## Repo map

| Path | What it is |
|---|---|
| `rig-lite/` | the kit: gate, worktrees, secrets, digest, token dashboard, memory pattern, spec templates, automation prompts, self-test |
| `demo/` | the recorded demo + its recorder + auth-guard (refuses to record logged-in sessions) |
| `.devcontainer/` | kit container: postCreate runs the self-test, installs tmux, wires the boot hook |
| `workspace.sh` | the 5-window tmux rig: claude · claude+ruflo · codex · tokens dashboard · shell |

## Working in this repo

Use `tf` (one command for everything — installed by init-repo.sh to ~/.local/bin):

- `tf gate --builder <cli>` — gate the current branch (vs main; reviewer ≠ builder's family)
- `tf test` — the fail-closed self-test suite
- `tf secrets set/get/rm/list` — encrypted secrets (names only when listing)
- `tf wt <name>` — isolated worktree per parallel writer
- `tf digest` — fleet health report
- `tf tokens --watch` — live token dashboard
- `tf status` — everything at a glance (repo, gate stats, session, tree)
- `tf init` — install the kit into any repo
- `tf protect` — enable branch protection (Law 2 enforcement)

Or use the long paths (`rig-lite/gate.sh`, `rig-lite/secret.sh`, etc.) — same tools.

- Durable facts: `rig-lite/memory/`, one fact per file, git-versioned
- Changes arrive by PR + gate. Builders never merge; humans do.

## Releases

- Bump the version in BOTH `package.json` and `CITATION.cff` — the self-test enforces parity (in the repo; the checks skip inside the npm package, where those files don't ship).
- `npm publish` runs on `v*` tags (`.github/workflows/npm-publish.yml`): the tag must equal the package version, versions already on the registry are skipped, and the `NPM_TOKEN` secret is required. The npm account has 2FA — publishing from Actions needs an automation (bypass-2FA) token; a regular token hits EOTP. v5.4.0 was published manually from a terminal with `npm publish`.
- Humans merge; agents cut and push the tag once the release PR has landed.

## Harnesses (by role, none bundled)

**ZCode builds · Claude Code reviews — with the Ruflo mod installed when you want orchestration · Codex backs up the review.**

The gate knows the builder families (`claude`, `codex`, `glm`/`zcode`/`zai`, `gemini`, `grok`, `xai`) and refuses to run unless it can find a reviewer from a family other than the builder's. `rig-lite/tokens.py` watches live token burn across zcode + claude + codex, read-only.
