# Turbo Brain — what to leverage from github.com/ruvnet

2026-08-16 · source-level audit of 8 repos · companion to TURBO-BRAIN-PLAN.md

**Question asked:** can we leverage something already built there?

**Answer:** yes — but patterns, not packages. Nothing in the ecosystem should
become a dependency of the vault. Several things should be stolen outright,
and one thing in your *existing* stack is actively hostile to the plan and
needs an opt-out set today.

Every claim below is backed by a file path from a source read, not a README.

---

## 1 · Verdict table

| Repo | Relevance | Verdict |
|---|---|---|
| `obsidian-brain` | markdown vault ↔ brain bridge — closest existing thing | **Take nothing structural.** Architecture is the exact inversion of ours |
| `agentdb` | candidate index layer | **DO-NOT-DEPEND** — reproduced: inserts report success, search returns zero |
| `agenticow` | candidate index layer | **Sound but wrong shape.** Honest code; stale-lock bricks the store after any crash |
| `ruflo` memory (`v3/src/memory/**`) | memory subsystem | **Ignore** — `Map` in RAM behind a class named `SQLiteBackend` |
| `ruflo` ledgers + ADR importer | run ledgers, markdown ingest | **Steal** — best prior art found anywhere |
| `ruflo` daemon autostart | — | **Actively avoid.** See §4 |
| `metaharness` scaffolded memory | memory + learning loop | **Ignore** — documentation with no implementation behind it |
| `metaharness` `kernel-js/session.ts` | append-only ledger | **Steal** — best-engineered file in any of these repos |
| `helix` | private local-first personal vault | **Steal the type design and two ADRs.** Avoid its storage model |
| `FACT` | retrieval without vectors | **Steal one pattern.** Its headline number came from a random number generator |

---

## 2 · The three things worth stealing, ranked

### 2.1 helix's provenance design — it beats ours

`crates/helix-provenance/src/lib.rs`. Three ideas we should adopt:

**Provenance gates combination, not just audit.** Their `MeasurementMethod`
is a closed enum, and the stated reason is that the engine uses it to decide
*whether two values may be compared at all* — "you do not trend a manual
entry against a lab-feed value without flagging the method change." Our
`[stated]/[ingested]/[derived]` tags are currently decoration: they record
where a fact came from and nothing reads them. Adopting the rule gives them
a job — **a distillation wave may not silently merge facts of differing
provenance.** A merge across tags must produce `[derived]` with both sources
cited, never a quiet rewrite.

**Provenance ≠ confidence — two axes, not one.** "Tier is what kind of
support; confidence is how solid this particular measurement is." A
`[stated]` fact can be shaky; an `[ingested]` one can be certain. We were
about to collapse these.

**Dangling citations are a hard reject, not a warning.** Their
`GroundedClaim` has no public constructor — the only way to get one is
`ground(draft, evidence)`, which fails on `NoCitations` or
`DanglingCitations`. Our linter checks `[[wikilinks]]` resolve but **does not
check that `(from: ...)` on a `[derived]` fact points at a file that
exists.** That is a real gap and it is fixed in this session (§5).

### 2.2 ruflo's ADR importer — wave-shaped markdown ingest that already works

`plugins/ruflo-adr/scripts/lib/parse-adrs.mjs`. It is a batch importer
invoked as a job, not a daemon — architecturally already our model. Its
hard-won lessons, free:

- **Stable logical key from content identity, never from time.** Their
  comment: "Timestamps describe an observation; they must not be part of
  identity or every index run creates another logically-identical edge."
  Observation time goes in the value (`capturedAt`), not the key. This is
  the single most important rule for our Phase 3 adapters — get it wrong and
  every wave duplicates every fact.
- **One ID normalizer, shared by the filename parser and the body-reference
  extractor.** They shipped a bug where `ADR-0001.md` and a body reference
  to `ADR-0001` produced different keys, silently dropping every edge.
- **Skip list by name, not heuristic:** `node_modules, .git, dist, .brain`.
  Note `.brain` — an unskipped vault containing clones indexed *1,415
  foreign records against 19 real ones*, and because `.brain` sorts before
  `docs`, an interrupted run indexed only the foreign ones.
- **Integrity checks the wave reports on:** dangling refs, and status
  contradictions between an edge and its frontmatter.

### 2.3 metaharness `SessionLog` + ruflo's improvement ledger — provable no-loss

`packages/kernel-js/src/session.ts` is hash-chained append-only JSONL with a
detail most people get wrong: canonical JSON sorts keys by **UTF-8 byte
order, not UTF-16 code-unit order**, so a Rust reader and a JS writer agree.

`harness-improvement-ledger.ts` adds the property we actually want:
`baselineRef == previous championRef`, computed as `chainIntact`, which a
single bad entry flips. Applied to the brain: **each distillation wave's
record references the prior wave's output hash, so "no wave silently dropped
facts" becomes provable rather than asserted.** That is the missing
enforcement half of our no-net-loss gate.

---

## 3 · Two ADRs from helix that pre-argue decisions we already made

Worth reading in full before Phase 4 — they are better-argued versions of
D8 and D7, including costs we hadn't priced.

**ADR-047, two planes.** "Shared open engine (public plane) … contains zero
user data … data-free by construction" vs "per-user private plane …
never present in any repository — public or private." That is exactly our
`turbo-brain` / `brain-vault` split, already defended. Also: "Owner is a
real user — 'User #1' is a role, not a privilege," which is the constraint
that keeps D10 (team brain) possible.

Its **Open Question 1** is the useful part: *"Does the public engine need a
hard CI guard that fails the build if any file resembling private-plane data
is staged? Strongly lean yes."* They never built it. Their "client data
never enters" enforcement is a `.gitignore` — which does not fire on
`git add -f`, on a rename, or on paste-into-a-note. **We built the gate they
proposed.** That is the clearest evidence D8 was worth the effort.

**ADR-049, scheduled per-source cadences.** "Scheduling is local-first —
launchd (macOS) or cron, on the user's own device — never a company-operated
job runner." Per-source cadence, one fault-isolated agent per source so one
failing source never blocks the others, watermark-based incremental fetch.
All matches D7.

The row we hadn't priced: **"silent staleness risk"**, mitigated by
surfacing per-source last-success. A wave that fails every night rots the
vault quietly. Adopted in §5.

---

## 4 · The finding that matters most: a daemon in your current stack

`v3/@claude-flow/cli/src/services/daemon-autostart.ts` — ruflo **spawns a
detached daemon on ordinary CLI invocation**, `stdio:'ignore'`, `unref()`'d.
Its own header explains why: the distillation, backup, and evolve workers
"are inert unless the daemon runs." Issue #2852 in the same file records it
spawning detached daemons in unrelated Claude projects until the marker
check was tightened.

Basic `memory store/retrieve` works daemon-free. **Consolidation,
distillation and "learning" do not.** That coupling is precisely what the
no-daemon stance in both plans rejects, and it is live in the stack Turbo
Flow sits on.

**Action, today, independent of Turbo Brain:**

```bash
export RUFLO_DAEMON_AUTOSTART=0          # or {"daemon":{"autostart":false}}
```

Then check for strays: `ls .claude-flow/daemon.pid` across your repos.

---

## 5 · What changed in the build as a result

Five amendments, all implemented and tested this session:

| # | Change | Source |
|---|---|---|
| 1 | **Dangling-citation check.** `[derived] (from: X)` and `[ingested] (src: X)` must resolve; unresolved is a lint error, not a warning | helix `GroundedClaim` |
| 2 | **Empty deny-list now fails closed.** A `CLIENTS.deny` with zero terms was a no-op gate reporting green — it now exits non-zero and refuses to pass vacuously | helix `check_safety_boundary.sh` |
| 3 | **`turbo-brain selftest`** — negative controls that plant a known secret and a known client term and assert both gates fire. Gates that cannot prove they work are decoration | helix negative-control commit `bf5277a` |
| 4 | **Per-source last-success tracking**, surfaced by `doctor` with a staleness threshold | helix ADR-049 |
| 5 | **`brain_recipes` MCP tool** — canonical worked-example searches shipped alongside the search tool | FACT's navigation triad |

On #5: FACT's one real idea is that deterministic retrieval works when the
model gets **data + structure + worked examples**, not just a search tool
(`SQL_QueryReadonly` / `SQL_GetSchema` / `SQL_GetSampleQueries`). Our
equivalent is `brain_search` + `brain_list` + a recipes tool. Most people
ship the search and skip the exemplars; the exemplars are what make a
no-index vault answerable.

---

## 6 · If and when D4 triggers, what to index with

Not agentdb. The failure is reproduced at HEAD and on the published alpha:
`insert()` returns a valid id, `search()` on the identical text in the same
process returns zero results, and `getStats()` throws `this.db.count is not a
function` — the adapter is written against a `ruvector` API that no longer
exists. The fallback chain never rescues you because it only fires when
`initialize()` throws, and it doesn't. Worse, with `@huggingface/transformers`
absent it prints "falling back to mock embeddings" and indexes your vault
with fake vectors while reporting success. Its one persistence test passes
because the vector backend is constructed in `beforeEach` and carried across
every simulated restart, so it cannot fail on index loss.

This is the same failure class your own ecosystem audit found in Aug 2026,
still live, and the strongest possible evidence for D1 (plain files) and D4
(no index in v1).

`agenticow` is the honest one — I have durability confirmed by a crash test,
a clean install with prebuilt binaries, and a README candid about its own
limits. But it stores `id → vector` only, loses `text` on unclean exit, and
an unclean exit leaves a stale `.rvf.lock` that makes every subsequent
`open()` throw `LockHeld` permanently, with no stale-lock detection anywhere.
For an index we can rebuild from git in seconds, that trade is bad.

**When D4 triggers: `sqlite-vec` or a flat numpy index.** Less machinery,
no lock semantics, and rebuildable from the markdown by definition.

---

## 7 · One line per repo, for the record

- **obsidian-brain** — markdown is an *input* copied into an authoritative
  SQLite+blob store with no DELETE endpoint and no reindex-from-directory
  path; needs two daemons; its "MCP server" is plain REST with no JSON-RPC
  anywhere, while the real MCP crate is a 20-tool read-write client hardwired
  to a hosted service. If the embedder is down, `create_memory` discards the
  error, returns `201 CREATED`, and stores a permanently unsearchable ghost
  the plugin will never retry.
- **agentdb** — see §6.
- **agenticow** — sound, narrow, honest; wrong shape for us.
- **ruflo** — three parallel non-interoperating memory implementations; the
  DDD one is a `Map`. The ledgers and the ADR importer are genuinely good.
- **metaharness** — the scaffolded "memory" is a SKILL.md describing commands
  that do not exist. `session.ts` is excellent.
- **helix** — real working software with real CI; the encrypted vault is
  well-tested but **not wired to the read path** (`analyze()` still takes
  plaintext), so the flagship privacy property is unproven end-to-end. Its
  type design is still the best thing in the ecosystem.
- **FACT** — the "sub-100ms" benchmark comes from
  `random.normalvariate(target*0.9, ...)` clamped so it cannot fail; a real
  run in the same repo, 30 minutes later, measured 1434ms average and a 0%
  cache hit rate. Prompt caching was configured and never passed to the API.
  The navigation triad is still a good idea.

**Standing lesson, applies to our own work:** in every one of these repos the
status documents asserted completion and the call sites disagreed. Check the
workflow file and the call sites, never the `*_STATUS.md`.
