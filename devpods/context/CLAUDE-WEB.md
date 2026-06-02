# CLAUDE.md — <PROJECT_NAME>

<!-- TurboFlow template. Lean variant for Claude Code web / lightweight sessions. -->
<!-- The full-stack (Beads/Ruflo/swarm) variant is CLAUDE.md. Use this one when working on the web. -->

`<stack one-liner, e.g. Next.js · React · Prisma · Postgres>`.
Always Opus, thinking ON. Pick the strongest model every task — slower per turn, fewer retries, faster overall.

## Workflow Orchestration

1. **Plan Mode Default** — Enter plan mode for any non-trivial task (3+ steps or architecture). Write the spec first to kill ambiguity; on the web, save the plan to the repo and commit before the cloud session executes it. If it goes sideways, stop and re-plan. Use plan mode for verification too, not just building.
2. **Subagent Strategy** — Use subagents liberally to keep the main context clean. Offload research, exploration, and parallel analysis. One responsibility per subagent. Throw more compute at hard problems via subagents.
3. **Self-Improvement Loop** — After ANY correction from the human, update `tasks/lessons.md` with the pattern and a rule to prevent the repeat. Review lessons at session start. Iterate until the mistake rate drops.
4. **Verification Before Done** — Never mark a task complete without proving it works. Diff behavior vs `main` when relevant. Ask: "would a staff engineer approve this?" Run tests, check logs, demonstrate correctness. Review with fresh context — never grade your own homework in the session that wrote the code.
5. **Demand Elegance (Balanced)** — For non-trivial changes, pause and ask "is there a more elegant way?" If a fix feels hacky, implement the proper solution. Skip this for simple, obvious fixes — don't over-engineer. Challenge your own work before presenting it.
6. **Autonomous Bug Fixing** — Given a bug report, just fix it. Point at logs, errors, failing tests, then resolve them. Go fix failing CI without being told how. Zero hand-holding.

## Task Management

1. **Plan First** — write the plan to `tasks/todo.md` with checkable items.
2. **Verify Plan** — check in with the human before starting implementation.
3. **Track Progress** — mark items complete as you go.
4. **Explain Changes** — high-level summary at each step.
5. **Document Results** — add a review section to `tasks/todo.md`.
6. **Capture Lessons** — update `tasks/lessons.md` after corrections.

## Core Principles

- **Simplicity First** — make every change as simple as possible; minimal code impact.
- **No Laziness** — find root causes, no temporary fixes, senior-developer standards.
- **Minimal Impact** — touch only what's necessary; no side effects, no new bugs.

## Guardrails

- Never merge or force-push to `main`/`prod` without explicit human "yes". Surface the diff and test status, then wait.
- Never commit secrets or `.env`. Confirm before any destructive command (`rm -rf`, `git reset --hard`, `prisma migrate reset`, `DROP TABLE`).

> This file is committed and shared. When Claude slips up, add ONE rule here — don't rewrite. Project-specific gotchas and tooling live in `docs/`.
