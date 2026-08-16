---
name: turbo-flow
description: AI-powered delivery harness — plan-implement-verify-ship loop
sources: [cowork, ledger]
aliases: [TurboFlow, Ruflo]
sensitivity: private
---
- [stated] Turbo Flow is a plan → implement → verify → ship harness for AI-powered delivery
- [stated] v5 decisions: no daemons, bash-first, plain files, budgets and gates on every turn
- [stated] The harness runs four phases: plan, implement, verify, ship
- [stated] Each phase has a budget cap, a max-retry count, and a hard stop
- [stated] Budget enforcement uses claude -p --max-budget-usd flag — binds mid-turn
- [stated] Human escalation is the one capability missing from the entire ruvnet ecosystem
- [stated] bin/lg is the single CLI entry point — one file, jq, and gh
- [stated] Run ledgers are the source of truth for what happened — every run writes state.json
- [ingested] Added budget-slope from continue-gate.ts — predictive not reactive cap checking (src: ruvnet-audit 2026-08-15)
- [ingested] Added circuit breaker from recovery.ts — stop retrying environmental failures (src: ruvnet-audit 2026-08-15)
- [ingested] Added classifyEntrypointResult — gate that exits 0 with no output never counts as pass (src: ruvnet-audit 2026-08-15)
- [derived] Ecosystem audit found nothing worth depending on — patterns only, not packages (from: areas/turbo-brain.md)
- Related: [[turbo-brain]], [[wa-signal]], [[agent-memory-ecosystem]]