# The git-versioned memory pattern

> Agents forget; git doesn't. This is the memory layout Turbo Rig
> agents use — portable to any agentic environment, no database, no
> Beads required. The diagrams next to this file (`loop.svg`,
> `memory-sync.svg`, `memory-lifecycle.svg`) show the full cycle.

## Layout

```
memory/
  MEMORY.md          # the index — the ONLY file loaded every session
  facts/
    deploy-needs-restart.md   # one fact per file, always
    api-rate-limit-found.md
```

**The index is the budget.** `MEMORY.md` holds one line per fact —
enough to decide *whether* to read the file, never the fact itself.
A session loads the index; topics get pulled on demand.

## One fact per file

```markdown
---
name: deploy-needs-restart
description: Railway deploys need a manual redeploy after plan changes
metadata:
  type: project        # user | feedback | project | reference
---

Railway Hobby→Pro requires `railway redeploy --service X --yes` after
the plan change; the port unblock does not apply until redeployed.

**Why:** discovered 2026-09-19 after a silent egress failure.
**How to apply:** always redeploy after plan/variable changes.
```

- `name`: kebab-case slug; other facts link to it `[[like-this]]`
- `description`: the one line that makes recall decisions possible
- `type`: who the fact belongs to — the agent's, the user's, or the
  project's
- Body: the fact, then **Why** and **How to apply** when it's a lesson

## Sync rules

1. **Write the memory in the session where you learned it** — not
   "later". Later never comes.
2. **Update, don't duplicate** — new fact about an existing topic?
   Edit that file. Two files about one thing is a bug.
3. **Delete wrong memories openly** — a commit that removes a stale
   fact is worth more than the fact was.
4. **Never store secrets.** Memory is committed. Ever.

## Lifecycle

```
learned → written (fact file + index line) → recalled by description
   → confirmed (stays) / contradicted (corrected or deleted, in git)
```

Facts that keep being wrong get deleted. Facts that keep being
recalled get promoted into runbooks — memory graduates into
documentation when it stops changing.
