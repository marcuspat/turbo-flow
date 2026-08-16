# Reuse assessment: ruvnet's stack vs. building the harness

Question asked: *don't reinvent the wheel — can MetaHarness (or Ruflo, or
dream-machine) supply the spec → graph → loop → escalation machinery?*

Answer: **no, and the reason is specific and checkable.** The wheel exists in
those repos as design. It does not exist as an installable artifact. Three
independent deep reads, all against source rather than READMEs, found the same
shape each time: the good component is real, tested, and stranded in a package
nothing installs.

Everything below is quoted from source at the commits current on 2026-08-15.

---

## 1 · The repo is not the artifact

This is the single most important finding, and it recurs in all three projects.

**Ruflo.** `ruflo` on npm is a wrapper with one dependency:
`"dependencies": { "@claude-flow/cli": "^3.33.0" }`, and
`bin/ruflo.js` says so in line 2 — *"thin wrapper around @claude-flow/cli with
ruflo branding"*. The packages the docs advertise are **not dependencies of the
CLI**:

| Package | What it holds | In CLI deps? | Version |
|---|---|---|---|
| `@claude-flow/swarm` | the real task DAG | **no** | `3.0.0-alpha.8` |
| `@claude-flow/guidance` | `ContinueGate` | **no** | `3.0.0-alpha.3` |
| `@claude-flow/hooks` | ReasoningBank guidance provider | **no** | `3.0.0-alpha.7` |

Verified by absence: `grep -rl "ContinueGate" dist/` → empty.
`find dist -iname "*task-orchestrator*"` → empty. The CLI is at 3.38.12 and
publishes roughly twice a day; those three sat at six-month-old alphas.

**MetaHarness.** `@metaharness/harness` is the package with the plan DAG, the
four-gate guard, the circuit breaker and the retry budget. It is 1,283 LOC, it
is unit-tested (62 tests pass in 2.4s), and
`grep -rl '"@metaharness/harness"' --include=package.json .` returns **only its
own package.json**. Nothing in the monorepo imports it. `npx metaharness` does
not install it. It reports 22,625 weekly npm downloads with zero dependents
anywhere — that is mirrors and CI, not use.

So "reuse MetaHarness" in practice means: vendor a few files from a repo, by
hand, and maintain them. Which is a legitimate thing to do — see §4 — but it is
not the same as taking a dependency on a maintained harness.

---

## 2 · What `npx metaharness` actually emits

21 files, 132 KB. The "agents" are not executable. `src/agents/implementer.ts`
in its entirety is three constants:

```ts
export const SYSTEM_PROMPT = `You implement the architect's plan. ...`;
export const NAME = 'implementer';
export const TIER = 'sonnet' as const;
```

Nothing reads them. The generated `bin/cli.js` implements four commands: `init`,
`doctor`, `--version`, `--help`. There is no agent loop, no LLM call, no
orchestration in the output.

Two defects worth knowing before you build on it:

- The generated `.claude/settings.json` registers an MCP server
  (`npx -y my-bot@latest mcp start`) that **cannot start** — the generated
  `bin/cli.js` has no `mcp` case and exits 2 with "Unknown command: mcp".
- **`harness verify` reports `VALID` and exits 0 on a placeholder signature.**
  Tested end to end: `harness sign` wrote a manifest whose public key was 64
  `a` characters and whose signature was 128 `b` characters; `harness verify`
  returned `VALID (shape verified; kernel witnessVerify unavailable — signature
  NOT cryptographically checked (degraded))`, exit 0. The cause is structural,
  not a packaging slip: no compile target exports witness. `crates/kernel-wasm`
  exports `kernelInfo, mcpValidate, autonomousValidate, sessionValidate,
  sessionStateHash, sessionReplay, version`; `kernel-napi` exports three
  functions; `witness.rs` is reachable only from `cargo test`. The source
  comment at `subcommands.ts:266` says the intent was *"no silent 'unsigned but
  accepted' state"* — that is exactly the state it produces.

If you were planning to lean on witness-signed releases as a client-facing
trust story, that is the finding that matters most.

---

## 3 · dream-machine is a prompt compiler, not an engine

It looked like the closest overlap — *"config-driven engine for nightly,
cloud-scheduled, evidence-gated repository evolution… behind a promotion gate
that never merges"*. In source:

- The "engine" is `packages/compile/src/index.ts`, 411 lines, which
  `sections.push()` 21 template functions and joins them into a **13,580-byte
  markdown document**. A human pastes that into Claude Code's `/schedule`.
- The promotion gate is nine words joined by `∧` **inside a template literal**
  (`index.ts:278-281`). Nothing computes those conjuncts. The model
  self-assesses.
- The nightly cron is **commented out** in the workflow, and the CI path
  hardcodes `const verdict = 'INCONCLUSIVE'; // GHA dream-lite is research-only`.
- Two of the three composed backends do not work as invoked, and the repo's own
  night report says so: `redblue: suspicious-silent (exit 0)` and
  `flywheel: blocked (exit 1) — npm error could not determine executable to run`.
- No budget field exists in the config. The budget "feature" is a paragraph
  beginning *"Set a budget before research"* with no unit, default, or key.
- The dashboard's ledger data is fabricated — disclosed in the JSON itself:
  *"Illustrative data for the dashboard — not the output of a real nightly run."*

Age and volume: created 2026-08-13, **17 commits**, 13 of them in a three-hour
window on day one, single author. A three.js tesseract, a 927-line
scrollytelling page and a 779-line dashboard were built the same day as the
411-line generator that constitutes the whole engine.

---

## 4 · What is genuinely worth taking

Three things, all MIT, all read-and-reimplement rather than depend-on.

**`@claude-flow/guidance/src/continue-gate.ts`** (533 lines, zero production
consumers, ships nowhere) is the best artifact any of these repos contains for
this problem. Its five-way decision is the right shape:

```
 * - continue:   Agent may proceed to next step
 * - checkpoint: Agent must save state before continuing
 * - throttle:   Agent should slow down or wait
 * - pause:      Agent should stop and await human review
 * - stop:       Agent must halt immediately
```

with `maxBudgetSlopePerStep` estimated by linear regression over spend history,
`maxReworkRatio`, and `minCoherenceForContinue`. Our `pass / blocking /
needs_human` verdict is the same idea with fewer states. **Budget *slope* is the
one genuinely better idea** — it catches a run that is going to blow the cap
before it does, rather than at the moment it does. Worth adding.

**`@metaharness/harness/src/recovery.ts`** — `CircuitBreaker`
(closed/open/half-open) and `RetryBudget(maxRetries, maxUsd)`. We have retry
bounds; we do not have a breaker that stops hammering a node whose failures are
environmental rather than fixable.

**`@metaharness/projects/src/scheduler.ts`** — the exhaustive typed termination
reason, which is better practice than our string statuses:

```ts
export type TerminationReason =
  | 'success' | 'budget_exhausted' | 'max_retries' | 'max_escalations'
  | 'max_reviewer_passes' | 'context_overflow' | 'security_uncertain';
```

Also worth stealing: dream-machine's `classifyEntrypointResult` (18 lines that
catch an evaluator exiting 0 with empty stdout **and** empty stderr — the silent
no-op that made `redblue` look like it passed), its `automerge.yml`
protected-path regex, and Ruflo's `hookCmd()` portability probe in
`settings-generator.ts:195-210`, which is hard-won and cost them several issues.

---

## 5 · The capability actually missing everywhere

**Human escalation.** Not "thin" — absent, in all three.

In both Ruflo and MetaHarness the word *escalation* means **escalating to a more
expensive model tier**: `frontierEscalationThreshold`, `maxFrontierEscalations`,
`const escalateTo = bestModel === 'haiku' ? 'sonnet' : 'opus'`. Ruflo's approval
path is explicitly unimplemented — `commands/policy.ts:88`: *"approval issuance
requires an authenticated human identity adapter"*. dream-machine's escalation
model is passive: open a draft PR and stop; if nobody looks at GitHub, nothing
happens. Searches for `gh issue comment`, `notify`, `slack`, `webhook`,
`needs.decision`, `blockedOnHuman` across all three return nothing that halts
and waits for a person.

Which means the thing you actually asked for — *"pings me if it needs
anything"* — is the one part no one in that ecosystem has built. That is not a
gap you can close by adopting a dependency.

---

## 6 · The one thing this research changed in our harness

`claude -p` has a **`--max-budget-usd`** flag. Ruflo uses it in exactly one
place (`services/fable-harness.ts`), and it is the only real budget enforcement
anywhere in their stack. From the CLI reference:

> Maximum dollar amount to spend on API calls before stopping (print mode only).
> Spend from subagents counts toward the cap. Once spend reaches the cap,
> spawning another subagent fails with `Budget limit reached`, and Claude Code
> stops background subagents that are still running.

`bin/lg` now computes `min(run budget left, node budget left)` and passes it on
every turn. That closes the caveat the README previously carried honestly — the
budget was checked *between* iterations, so a run could overshoot by one node.
Now the cap binds mid-turn and covers subagents. Verified: plan got `3.0000`,
implement `12.0000`, verify `6.0000`, ship `2.0000`, matching `graph.json`.

One real capability, found by reading their source, worth the whole exercise.

---

## 7 · Risk, if you were considering a dependency anyway

| | Ruflo | MetaHarness | dream-machine |
|---|---|---|---|
| Age | mature (2025-06) | 2026-06 | **2 days** |
| Commits, single author | 81/100 recent | 860/919 | **17/17** |
| Release cadence | ~2 npm/day, 375 versions | 40 npm, 3 GH releases | 1 |
| Tests | 552 files, **0 shipped**, baseline records **116 failing** | 334 files, real, pass | 96, pass |
| CI honesty | lint/typecheck `continue-on-error: true` | CodeQL, cargo-deny, SBOM | node 18/20/22 matrix |
| Velocity now | high | **~95% drop since July 8** | n/a |
| Open issues | 559 | 29 | 2 |

Ruflo's third-party issues share one theme, and it is the worst possible theme
for unattended work: **silent failure**. *"memory store reports success but
persists nothing"* (#2968). *"8 agentdb exports no installable agentdb
provides — native controllers silently dead on every fresh install"* (#2977).
*"`ruflo mcp start` silently strips manually-installed packages on every fresh
launch"* (#2946).

Credit where it is due: Ruflo's own `CLAUDE.md` retracts its headline
benchmarks — HNSW is *"~1.9x at N=20k… (150x-12,500x **NOT reproduced** — was
brute-force fallback)"*, and Flash Attention's numbers are *"inherited from
upstream marketing, never reproduced in-tree."* That is unusually honest and it
is the right instinct to trust in the author. It is also the reason to read the
source rather than the README everywhere else.

For a rig you put in front of paying clients, a 290-file install from a
single-maintainer project shipping twice a day with 116 known-failing tests is
not a footprint you want inside a delivery contract. `bin/lg` is one file, jq,
and `gh`.

---

## What to do

1. **Keep the harness.** Every requirement you named is either absent or
   unwired in all three projects. You are ahead on substance.
2. **Add budget-slope** from `continue-gate.ts` — predictive rather than
   reactive cap checking.
3. **Add a circuit breaker** from `recovery.ts` — stop retrying environmental
   failures.
4. **Add `classifyEntrypointResult`** to the gate runner — a gate that exits 0
   with no output should never count as a pass. dream-machine found that bug in
   their own dependencies; it is worth inoculating against.
5. **Do not use `harness sign` / `harness verify` for anything you would
   attest to a client.**
6. **Revisit MetaHarness for the Turbo-Flow repositioning specifically.** That
   plan — mint a branded `npx turbo-flow` CLI identity with kernels as versioned
   deps — is about *packaging and identity*, which is exactly what the
   scaffolder does well. It is the wrong tool for the control plane and a
   reasonable one for the wrapper. Those are separable decisions and this
   assessment only settles the first.
