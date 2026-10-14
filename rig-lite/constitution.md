# Constitution — template for agentic coding agents

> Fill in the brackets, drop this where your agents read instructions
> (CLAUDE.md, AGENTS.md, system prompt), and hold the line. A
> constitution is only real if it is enforced — pair it with
> `gate.sh` so the laws have teeth, and `protect.sh` so Law 2 is
> enforced by GitHub, not by agent restraint.

## The Laws

1. **Builder ≠ reviewer.** Every change is reviewed read-only by an
   agent from a *different model family* than the one that wrote it.
   Same-family self-review does not count as review.
2. **Agents never merge.** No agent force-pushes, merges, or pushes to
   the mainline. Humans hold the merge button. Always.
   **Enforced by `protect.sh`** — which turns this law into GitHub
   branch protection: the `gate-verdict` status check must pass before
   any merge, and only the gate's APPROVED verdict makes it pass. An
   agent with merge-capable credentials is still blocked, because
   GitHub's servers refuse the merge, not the agent's good behavior.
3. **Parallel writers get isolated worktrees.** Two agents never write
   the same checkout. One writer per worktree, one lane per branch.
4. **Secrets never touch git.** Credentials live in the OS keychain or
   a gitignored env file — never in code, commits, logs, or issue
   bodies.

## Deterministic before expensive

Cheap checks run first and cost nothing: lint, tests, type-check,
syntax. Paid model review only happens after the free checks pass.
This is both an economics rule and a signal rule — a diff that fails
`tsc` doesn't need a model to tell you.

## Verdicts are parseable or they don't exist

The reviewing agent must end with exactly `VERDICT: APPROVED` or
`VERDICT: REVISE`. Ambiguity, hedging, or a missing verdict line is
REVISE. Fail-closed, always.

## Memory is versioned, not vibes

Cross-session memory lives in git (one fact per file + an index), not
in a chat transcript. If it mattered, it's written down; if it's
wrong, it gets corrected with a commit, not a hope.

## State on disk, not in chat

- Specs: [`specs/`] *(pre-merge plans, numbered)*
- Memory: [`memory/`] *(durable facts + index)*
- Runbooks: [`runbooks/`] *(how operations are actually done)*

## When in doubt

Ask the human. Blocking on a question for two minutes is cheaper than
a week of unmergable work.
