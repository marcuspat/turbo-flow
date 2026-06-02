# CLAUDE.md — <PROJECT_NAME>

<!-- TurboFlow template. Full-stack / terminal sessions. The lean web variant is CLAUDE_WEB.md. -->
<!-- Fill the <PLACEHOLDERS> per repo. Keep this file under ~200 lines. -->

```
PROJECT_ID = <project-id>
STACK      = <e.g. Next.js · React · Prisma · Postgres (prod) / SQLite (dev) · Railway>
MODEL      = Claude Opus (default, thinking ON) · GLM-5.1 = compatible fallback
```

> Issue tracking, blockers, decisions, and current work live in **Beads**, never in this file or markdown TODOs.
> Detailed command catalogs live in `docs/TOOLING.md`. This file is rules + conventions + the commands you use every session.
> Lean on native Claude Code (plan mode, subagents, slash commands, Stop hook). Don't reimplement what the tool already does.

---

## HARD RULES (never break)

- **NEVER merge to `main`/`master`/`prod`/`release` without the Triple-Gate Protocol.**
- **NEVER force-push to `main`.**
- NEVER commit secrets, credentials, or `.env` files.
- NEVER read or write `.beads/issues.jsonl` directly — the command is `bd`, not `beads`.
- Destructive commands (`git reset --hard`, `rm -rf`, `prisma migrate reset`, `DROP TABLE`) need one confirmation:
  `⚠️ DESTRUCTIVE: [command]. [consequence]. Confirm?`

## WORKING RULES

- Do exactly what's asked — nothing more, nothing less.
- Read a file before editing it.
- Don't create files (especially `.md`/README) unless necessary — prefer editing existing ones.
- Never write working files or tests to the repo root.
- Non-interactive flags only (`cp -f`, `mv -f`, `rm -f`); `--json` on every `bd` command.
- Run tests before committing (if a suite exists).
- After **3 failed attempts** at the same problem → STOP and ask the human.
- Batch related operations (todos, agent spawns, file ops, memory ops) into a single message.

## HOW TO WORK

- **Plan first** for any non-trivial task (3+ steps or architectural decisions). Enter plan mode, write the spec, then build. If it goes sideways, stop and re-plan — don't push a broken approach.
- **Verify before "done"** — prove it works with tests/logs, and diff vs `main` when relevant. Ask: *"would a staff engineer approve this?"*
- **Fix the system, not the symptom** — if a fix feels hacky, implement the proper one. Skip this for trivial, obvious fixes; don't over-engineer.
- **Be autonomous** — given a bug report or failing CI, just fix it. Point at logs/errors, then resolve them.
- **Use subagents** to keep the main context clean — one focused task each, for research, exploration, and parallel analysis.
- **Review with fresh context** — never review your own code in the same session that wrote it. Start a clean session for PR/code review.
- **Self-heal** — after any human correction:
  `bd remember "lesson/<topic>" "what went wrong + the rule to prevent it"`
  Review past lessons at session start.

---

## TRIPLE-GATE MERGE PROTOCOL

Any merge into `main` = 3 consecutive human confirmations, each a separate turn. No agent merges autonomously. Does **not** apply to feature-to-feature merges.

```
GATE 1 — "🔒 MERGE GATE 1/3: Merging [branch] → main. [changes, risk]. Confirm?"
GATE 2 — "🔒 MERGE GATE 2/3: Tests: [pass/fail]. Conflicts: [y/n]. Confirm?"
GATE 3 — "🔒 MERGE GATE 3/3: FINAL. Type 'yes' to execute."
```

Any non-`yes` aborts.

**Rollback** (skips Triple-Gate): `git revert --no-commit HEAD` → test → commit → push → tell human → `bd create` the bug → `bd remember "revert/[branch]" "cause"`.

**Conflicts** — never silently auto-resolve. Simple: resolve and show. Complex: show both sides, ask.

---

## MODEL

- **Opus is default, thinking ON.** Strongest model on every task — slower per turn, fewer retries, faster overall. Give it the full task and let it plan and chain steps; don't pre-chunk work or hand-hold its output.
- **GLM-5.1** is a deliberate fallback for cheap/bulk passes. Only switch on purpose, not by default.
  - *When running GLM:* generate complete files in one pass for new files >100 lines (don't chunk); give the full task context up front and let it chain steps; 200K context / 131K max output.
- **MCP first, CLI fallback** — prefer MCP tools; if a call fails, use the CLI equivalent (`bd`, `npx ruflo`, `npx gitnexus`). `npx ruflo@latest doctor --fix` checks registration.
- **Context hygiene** — `--json` on `bd`; `bd compact` when it fills; offload long explanations to `bd comments` / `memory store` instead of chat.

---

## SESSION WORKFLOW

**Start**
```bash
npx ruflo@latest hooks session-start --session-id <project-id> --start-daemon
bd ready --json && bd list --type blocker --json
npx ruflo@latest memory search -q "lesson" --limit 10
```

**Before non-trivial work:** `agentdb_pattern-search` → `mem-search` → `hooks route "<task>"` (a known solution may already exist).

**During:** claim the bead → record findings in `bd comments` → `bd create` discovered work → `hooks post-edit --file <f> --train-patterns` after significant edits.

**After a task:** verify it works → `bd close --reason "what+why"` → `agentdb_pattern-store` if novel → `memory store` → `hooks post-task`.

**End**
```bash
bd create   # remaining work, full descriptions
bd close    # finished work
<test+build+gate command, e.g. npm test && npm run build && aqe-gate>
bd dolt push && git push          # NOT done until git push succeeds — YOU push
npx ruflo@latest hooks session-end --export-metrics true --persist-patterns true
```

---

## BEADS (project truth)

Every `bd create` MUST include a self-sufficient `--description` (assume the reader never saw this chat). Run `bd sync flush` after batch ops.

```bash
bd ready --json                              # unblocked work
bd update <id> --claim --json                # claim before starting
bd comments add <id> "progress" --json       # findings mid-task
bd close <id> --reason "what+why" --json     # complete (prove it first)
bd remember "key" "value"                    # persistent knowledge
bd stale && bd orphans && bd lint            # hygiene
```

**Create pattern** — `bug | feature | task | epic | chore`, priority `0` critical → `4` backlog:
```bash
bd create "Title" \
  --description="what · where to wire it · repro or acceptance criteria" \
  -t bug -p 1 --json
# sub-task: --parent <id>   discovered: --deps discovered-from:<id>
# blocked:  --status blocked + a blocker with --deps blocks:<id>
```

Memory / patterns: `mem-search` before solving, `memory store --namespace <project-id> --key "area/fix" --value "what+why"` after. `agentdb_pattern-search` before writing fix code. Full hook & AgentDB catalog → `docs/TOOLING.md`.

---

## PARALLEL EXECUTION

- **Subagents (default for parallelism):** spawn with single responsibilities, one task each, to keep the main context clean.
- **Swarm:** hierarchical topology, spawn all agents in one message.
  `npx ruflo@latest swarm init --topology hierarchical --max-agents 8 --strategy specialized`
- **Worktrees:** one per agent, each with its own `$DATABASE_SCHEMA`; test before merge; `wt-clean` after.
  `git worktree add .worktrees/feat-a -b feat/feat-a`
- **Agent teams:** `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, lead → up to 3 teammates (depth 2). Sub-agents **cannot** merge to main. Requires `ANTHROPIC_API_KEY` in `~/.bashrc` — verify with `echo $ANTHROPIC_API_KEY`.

## GITNEXUS

Before editing shared symbols, run blast radius: `gitnexus_impact({target, direction: "upstream"})` — HIGH/CRITICAL = warn the human. Pre-commit: `gitnexus_detect_changes({scope: "staged"})`. Never find-and-replace symbols — use `gitnexus_rename`. Stale index → `npx gitnexus analyze`.

## QUALITY & SECURITY

`aqe-gate` (required before merge) · `aqe-generate` (tests for new code) · `npx ruflo@latest security scan --depth full` · `... security cve --check`.

---

## CONVENTIONS & GOTCHAS  <!-- per-repo: replace with this project's real gotchas -->

- `<framework gotcha, e.g. Next.js 16 async params: { params }: { params: Promise<{ id: string }> } then const { id } = await params>`
- `<ORM / migration note, e.g. Prisma prod sync: cp prisma/schema.prisma prisma/schema.prod.prisma after every schema change>`
- `<deploy note, e.g. Railway: builder = DOCKERFILE; healthcheckTimeout ≥ 5000ms; 502 → check migrations; build fails → TS errors>`

**Env — required:** `<DATABASE_URL>`, `<...>`
**Other / optional:** `<...>`

## STATUS HUD (after action responses, not pure conversation)

```
───────────────────────────────────
📍 Branch: <branch> · <N> files changed
🧪 Tests: <status> · ⚡ Model: Opus | GLM-5.1
───────────────────────────────────
```
