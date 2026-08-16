# Turbo Brain — Implementation Plan

2026-08-15 · sibling to TURBO-HARNESS-PLAN.md · supersedes
TURBO-BRAIN-PLANNING-BRIEF.md §6

**Decision criterion (adopted, same as v5): minimize risk, prefer the
cheapest reversal.** Every ruling below carries its reversal cost. Where two
options were close, the one that can be undone with a `git revert` beat the
one that needs a migration.

---

## 1 · Definition (attacked, then rewritten)

The brief's sentence — "a personal, cross-project memory layer — plain files
first — that follows Marcus across every repo, client, surface, and agent" —
fails on two words.

- **"memory layer"** implies automatic recall. Nothing here is automatic; a
  file is only useful because someone decided it was worth keeping. Calling
  it memory sets the expectation that it self-populates, which is exactly the
  failure mode the ecosystem audit found (stores that report success and
  persist nothing).
- **"follows"** implies sync machinery. It doesn't follow anything; it sits
  in one place and hosts reach into it.

Survivor:

> **Turbo Brain is an owned, portable context vault — plain markdown in git —
> that any agent on any host can read, so a session starts with the subtext
> instead of asking for it.**

**Success metric (single, measurable):** the *unnecessary-question rate* —
count of questions a session asks whose answer was already in the vault,
per 10 sessions. Baseline it in Phase 1 by hand-tagging 10 sessions. Target:
down 70% by end of Phase 3. If this number doesn't move, the project is
storage theater and should be killed rather than extended.

**Anti-goal:** the vault does not store procedures for thinking. Facts and
context only (principle 3). A file that reads like a prompt is a bug.

---

## 2 · Decisions closed

### D1 — Name & repo · **`turbo-brain` (public tooling) + `brain-vault` (private content)**

Two repos, split at the schema boundary:

| Repo | Visibility | Contents |
|---|---|---|
| `turbo-brain` | public, MIT | schema spec, JSON-Schema/lint for frontmatter, distillation wave specs, `turbo-brain` CLI, read-only MCP server, adapter interface + reference adapters |
| `brain-vault` | private | the content. Nothing but markdown and a `.turbo-brain.toml` pointing at the tool version |
| `brain-intake` | private | raw captures. Separate repo *because of D8's deletion story*, not for tidiness |

Rationale: the tooling is the part with reuse value and zero privacy risk;
the content is the part with total privacy risk and zero reuse value. Any
other split puts a privacy decision inside a publishing decision.

*Reversal cost:* low. Merging three repos into one is a day. Splitting a
single repo *after* content has accumulated history is a filter-repo job —
which is precisely why the split happens on day one.

### D2 — The Cowork/claude.ai memory line · **seed once, then strictly parallel; digest-out is a triggered later phase**

- **One-time seed (Phase 1):** the existing 24 Anthropic memory files are the
  best-curated personal corpus that exists right now. Export them into
  `brain-vault` as the initial `profile/`, `areas/`, `people/`, `topics/`.
  This is a seed, not a sync — it runs once and is never repeated.
- **Steady state (Phase 1–3):** strictly parallel. Anthropic memory keeps
  doing conversational continuity across Claude surfaces. The vault is the
  owned, portable source of truth. No coupling, so no drift to reconcile and
  nothing to debug when one of them is wrong.
- **Digest-out (Phase 5, triggered):** a monthly wave writes a ≤2KB digest
  from the vault into Anthropic memory — *only* once the vault holds material
  facts that Anthropic memory does not. Trigger condition: two consecutive
  months where the distillation wave produces ≥10 curated facts with no
  Anthropic-memory counterpart.

Rejected: bidirectional sync. It buys completeness and costs a permanent
merge-conflict problem across a store you don't control the write path to.
Not a v1 problem.

*Reversal cost:* near zero — parallel means there is nothing to unwind.

### D3 — Store format · **steal the Claude memory format outright, plus two fields**

```markdown
---
name: turbo-flow                    # path stem, unique across the vault
description: one line — what this covers, when to read it
sources: [cowork, wa-signal, ledger]
aliases: [TurboFlow, Ruflo]
sensitivity: private                # private | shareable | public
---
- [stated] one fact per line
- [ingested] fact pulled from an adapter (src: wa-signal 2026-08-12)
- [derived] fact a distillation wave concluded (from: areas/turbo-flow.md)
- Related: [[wa-signal]], [[loop-engineering]]
```

Rules:

1. **One fact per line**, prefixed with exactly one provenance tag:
   `[stated]` (Marcus said it), `[ingested]` (an adapter carried it in, with
   `src:`), `[derived]` (a wave concluded it, with `from:`). A line with no
   tag is a lint failure.
2. **`sensitivity:`** is new. It is what makes D10 possible later without a
   migration, and what the privacy gate reads. Default `private`; a file only
   becomes `shareable` by explicit edit.
3. **`sources:`** is append-only, same discipline as the Claude memory format.
4. **`[[wikilinks]]`** for cross-file relations — greppable, and free graph
   structure if a retrieval layer ever lands.
5. **One file per subject.** A fact about X goes only in X's file. Enforced
   by the dedup gate, not by hope.

Layout (strawman §4, kept nearly whole — see §4 below for the two changes).

*Reversal cost:* medium-low. Frontmatter migrations across a few hundred
markdown files are a scripted afternoon. The expensive mistake would be
*not* having `sensitivity:` and needing to hand-classify later.

### D4 — Retrieval layer · **none in v1. `rg` + directory structure.**

The vault at realistic personal scale is a few hundred curated files and low
single-digit MB. `rg` returns in milliseconds. An index at this scale is a
liability that can silently go stale.

**Explicit trigger to add one** — any of:

- curated corpus (excluding `intake/`) exceeds **3 MB** of markdown, or
- a representative 20-query benchmark returns **>200 candidate lines** on
  average, or
- the distillation wave's read budget exceeds **50k tokens** per run because
  it can't narrow.

When triggered: the index lands in `index/`, is **gitignored**, is rebuilt by
one command from the files, and is never consulted for writes. Source of
truth stays the markdown, permanently (principle 1).

*Reversal cost:* zero. Not building a thing has no reversal cost. This is the
cheapest decision on the list and the one the ecosystem audit most directly
earned.

### D5 — Ingestion order · **run ledgers + wa-signal. The other six wait.**

Ranked by value ÷ plumbing cost:

| Source | Value | Plumbing | v1? |
|---|---|---|---|
| Turbo Flow run ledgers (`.lg/runs/*/state.json`) | high — project distillate, and the dogfood rule demands it | trivial — JSON on local disk, seam already spec'd in v5 | **yes** |
| wa-signal | high — 153k events, bilingual, already chunked into ~25.7k chunks | near-zero — extraction, marts, chunking all built; only the distillate hand-off is new | **yes** |
| Notion | high | medium — MCP live, but it's where client material lives → biggest D8 exposure | Phase 5 |
| Gmail / company email | medium | high — noisiest source, needs a filter policy before it's anything but landfill | Phase 5 |
| Apple Notes | medium | medium — export is the flakiest link on the Mac | later |
| Reddit / X / LinkedIn saved | low density | low | later |
| Browser bookmarks | — | — | **never** (not a real source for him) |
| Google Docs | low | medium | later |

Two, not eight. An adapter that runs weekly and produces nothing is worse
than no adapter, because it teaches you to stop reading the output.

*Reversal cost:* zero. Adapters are additive behind a stable interface.

### D6 — Capture UX · **iOS Shortcut → GitHub Contents API, one file per capture**

This is the decision the project lives or dies on, so it gets the design that
has the fewest moving parts *at capture time*:

- Shortcut (share sheet + "Hey Siri, brain …" dictation) →
  `PUT /repos/marcuspat/brain-intake/contents/inbox/<ISO8601>-<slug>.md`
- **One new file per capture.** No read-modify-write, therefore no `sha`
  fetch, no append conflicts, no merge. A single HTTP call.
- Fails offline → Shortcuts retries; nothing is lost and nothing is
  half-written.
- No LLM in the capture path. Capture must cost zero tokens and zero seconds
  of thought. Distillation is where intelligence goes.

Rejected — **Cowork message → scheduled task**: it is the surface he already
lives in, but it puts a token cost on every stray thought, and he deleted his
existing Cowork tasks precisely because loops were burning tokens. Making the
cheapest, highest-frequency action in the system the most expensive one is
backwards.

Deferred as a *second* path (Phase 4, additive): **email dropbox** —
`brain@…` with a poller committing to the same `inbox/`. It's the only way
to forward from LinkedIn/Reddit/Gmail share sheets, so it earns its place
later, but the Shortcut ships first and alone.

*Reversal cost:* zero. The intake contract is "markdown files land in
`inbox/`". Any number of capture paths can write to it; swapping one out
touches nothing downstream.

### D7 — Distillation cadence + budget · **three waves, hard caps, deletions proposed not applied**

| Wave | Cadence | Cap | Job | Gates |
|---|---|---|---|---|
| **triage** | daily, 06:00 local | $0.50 | classify `inbox/` items, route to a target file, do *not* rewrite | secret-scan, privacy-deny |
| **distill** | weekly, Sun | $5.00 | intake → curated `areas/` `people/` `projects/` `topics/`; propose deletions and merges | secret-scan, privacy-deny, schema-lint, dedup |
| **sweep** | monthly | $3.00 | staleness pass, contradiction detection, `sources:` hygiene, orphan `[[links]]` | schema-lint, dedup, no-net-loss |

Rules:

- **Waves, not a daemon.** Same stance and same reasoning as v5 — scheduled
  invocations with budgets and gates, nothing resident.
- **The `no-net-loss` gate:** a wave may never reduce total curated fact
  count by more than 5% in one run. Deletions above that threshold are
  written to `proposals/<date>-deletions.md` and applied only after review.
  Silent forgetting is the failure mode that would make the vault untrustable.
- **Budget exceeded → wave stops and reports.** It does not degrade quality
  to fit.

*Reversal cost:* zero — cadence and caps are config lines.

### D8 — Privacy enforcement · **three mechanical layers + history-free intake**

**Layer 1 — deny at the boundary.** `turbo-brain` ships a `CLIENTS.deny`
file (client names, domains, repo slugs, project codenames). Every wave runs
a deny-scan before writing; a match aborts the write and quarantines the item
to `quarantine/`. Deny-list lives in the *private* vault repo, never in the
public tooling repo.

**`quarantine/` is gitignored** — amended during the Phase 0 build. Committing
caught client material into the repo would defeat the gate that caught it.
Quarantined files exist on local disk only, are never pushed, and are deleted
by hand after review.

**Layer 2 — secret-scan gate.** Reuse his own `Secret-Scan` on every intake
commit as a pre-commit hook and again in the wave gate. Cheap, obviously
right, and it dogfoods his own tool.

**Layer 3 — guard hook path rules.** The harness guard hook denies any brain
wave writing outside the three brain repos, and denies any *other* wave
writing *into* them. The seam stays one-way in both directions, same
discipline as v5's `brain.path` and the CTM pattern graph.

**Deletion story — intake is history-free locally, history-hidden on the
remote** (corrected in v1.1 after verification against GitHub's documented
behavior — a force-push leaves old commits fetchable by SHA indefinitely;
there is no automatic server-side GC):

- `brain-intake` is **squashed on rotate**: after each weekly distill wave,
  the repo is re-orphaned to a single commit containing only undistilled
  items. Local deletion is real; remote deletion is "unreachable from refs."
  Practical exposure is low (private, no forks, no PRs) and the escalation
  for genuinely sensitive material is delete+recreate of the repo, which
  bounds the tail at GitHub's 90-day restore window. See
  `docs/REDACTION.md`.
- `brain-vault` **keeps full history** — curated facts are the audit trail
  and their history is the point. Hard removal there is rare and follows a
  documented `git filter-repo` SOP in `turbo-brain/docs/REDACTION.md`.
- Consequence, stated plainly: anything that must be truly unrecoverable
  must never reach `brain-vault`. That is what Layers 1–2 are for.

*Reversal cost:* low going forward, **high if deferred**. Retrofitting
history-free intake after six months of captures means rewriting history that
may already be on a remote. This is the one decision that must not slip.

### D9 — Voice-babble · **later. Phase 6, unpriced.**

It is a capture modality plus an output modality wearing one name. The
capture half is subsumed by D6 (Shortcut dictation already lands text). The
output half — paralinguistic read → vault cross-reference → artifact — is a
separate product and deserves its own brief. Explicitly not dropped;
explicitly not v1.

### D10 — Enterprise / team brain · **separate commercial track, but two design constraints land now**

Not in scope as a phase. It is a CTM commercial offering, not a feature of a
personal vault, and mixing them would put a product roadmap inside a private
repo.

Two cheap constraints adopted now so the door stays open:

1. **No single-owner assumptions in the schema.** The vault root is a
   parameter, not a constant. `~/brain` is a default, not an invariant.
2. **`sensitivity:` exists from day one** (D3). A team brain is exactly the
   `shareable` subset of one schema; without that field it's a migration.

*Reversal cost of these two constraints:* effectively zero. Reversal cost of
*omitting* them: a schema migration across the whole vault later.

---

## 3 · What each existing asset becomes

| Asset | Ruling |
|---|---|
| Cowork / claude.ai memory | **Interface** — seed source once (D2), parallel thereafter |
| AgentDB / .rvf experiments | **Leave alone.** They're index-shaped; D4 says no index in v1. Revisit only if D4's trigger fires |
| wa-signal | **Absorb as adapter #2.** Nothing about wa-signal changes; a new distillate hand-off reads its marts |
| Daily AI Command Core (v7) | **Interface, both directions.** Produces `daily/<date>.md`; consumes vault context. No dependency either way |
| Named intake backlog (8 sources) | **Deferred** per D5 |
| Voice-babble | **Parked** per D9 |
| CTM pattern graph | **Leave alone.** Read-only, never merged. Guard-hook enforced (D8 L3) |
| Turbo Flow v5 | **One seam, two directions**: `brain.path` in, run ledgers out. No dependency either way |

---

## 4 · Layout (strawman kept, two changes)

```
brain-vault/                    # private, full history
  profile/                      # who I am, standing context, preferences
  areas/<name>.md               # ongoing involvements
  people/<name>.md              # relationship context
  projects/<repo>.md            # per-project distillate (fed by run ledgers)
  topics/<domain>.md            # ← ADDED: domain facts that aren't an involvement
  daily/<date>.md               # Command Core check-ins, day state
  proposals/<date>-*.md         # ← ADDED: wave output awaiting review (D7 no-net-loss)
  CLIENTS.deny                  # privacy deny-list (D8 L1)
  .turbo-brain.toml             # pins tooling version, sets vault root

brain-intake/                   # private, squashed on rotate (D8)
  inbox/<ISO>-<slug>.md         # one file per capture (D6)
  <source>/...                  # adapter output awaiting distillation
  quarantine/                   # GITIGNORED — deny-scan hits, never committed

index/                          # gitignored, absent in v1 (D4)
```

Two changes from the brief's strawman: `topics/` added (the Claude memory
taxonomy has it and it's load-bearing — "Rust tooling preferences" is not an
area, a person, or a project); `proposals/` added (D7's no-net-loss gate
needs somewhere to put what it didn't apply). `intake/inbox.md` as a single
append-only file is **killed** — D6's one-file-per-capture makes it a merge
hazard for no benefit.

---

## 5 · Phases

**Dogfood rule (inherited from v5, non-negotiable):** every phase below is
built by running harness waves, and the first thing the brain ingests is its
own run ledgers.

### Phase 0 — Capture is alive (target: 1 session)

The only thing that matters is that a thought from a phone lands in git.

- `brain-intake` repo, private, `inbox/` + `quarantine/`
- Secret-scan pre-commit hook (D8 L2)
- iOS Shortcut: share sheet + Siri dictation → Contents API PUT (D6)
- Rotate script: `turbo-brain intake rotate` (orphan-squash)

**Exit criteria:** 10 captures from phone in a single day, zero failures,
median capture time under 5s wall-clock. Secret-scan hook demonstrably blocks
a planted fake key.

**Kill signal:** if he doesn't use it unprompted in week 1, the capture design
is wrong and Phase 1 does not start.

### Phase 1 — Vault exists and is readable (target: 1 session)

- `brain-vault` repo + schema + `turbo-brain lint`
- One-time seed from Anthropic memory (D2) — 24 files → `profile/` `areas/`
  `people/` `topics/`, re-tagged to the D3 format
- Read path A: `brain.path` (the v5 seam — nothing new needed on the v5 side)
- Read path B: read-only MCP server, single tool `brain_search` (rg-backed),
  for surfaces that can't mount the path (GLM/Discord, Cowork)
- **Baseline the success metric**: hand-tag 10 sessions for
  unnecessary-question rate

**Exit criteria:** a fresh Claude Code session, a Codex session, and one
non-Claude host all answer "what is Turbo Flow's v5 stance on daemons?"
correctly with no context beyond vault access. Lint passes on all seeded
files.

### Phase 2 — Distillation wave (target: 1–2 sessions)

- `distill` wave spec + gates (secret-scan, deny, lint, dedup, no-net-loss)
- `triage` wave spec
- Scheduled via the harness runner, budgets per D7
- `proposals/` review flow

**Exit criteria:** one full week of captures distilled with zero manual edits
required; the no-net-loss gate demonstrably fires on a synthetic
over-deletion; total weekly spend under cap.

### Phase 3 — Two adapters (target: 2 sessions)

- Adapter interface in `turbo-brain` (input: source → output: intake files
  with `[ingested]` tags and `src:`)
- Adapter 1: run ledgers → `projects/<repo>.md`
- Adapter 2: wa-signal marts → `people/` + `areas/` distillate

**Exit criteria:** `projects/turbo-flow.md` is generated, not written by
hand, and is accurate. wa-signal produces ≥20 curated facts that survive the
distill wave. **Re-measure the success metric** — this is the go/no-go on
whether the hidden-context thesis holds.

### Phase 4 — Hardening (target: 1 session)

- Email dropbox as capture path #2
- `sweep` wave
- Guard-hook path rules (D8 L3)
- `docs/REDACTION.md` SOP
- Publish `turbo-brain` public repo (tooling only; content never)

**Exit criteria:** a planted client name in intake is quarantined, not
distilled. Public repo has zero content leakage — verified by a full-history
scan before first push.

### Phase 5 — Triggered work only

Nothing here starts on a date; each starts when its trigger fires.

- Retrieval index — trigger per D4
- Digest-out to Anthropic memory — trigger per D2
- Notion + Gmail adapters — trigger: Phases 0–3 stable for 30 days and the
  deny-list has caught ≥1 real client item (proving Layer 1 works before
  pointing it at the source with the most client material)

### Phase 6 — Separate briefs

- Voice-babble (D9)
- Enterprise / team brain (D10)

---

## 6 · Risk register

| Risk | Likelihood | Mitigation | Owner decision |
|---|---|---|---|
| Capture friction kills the project | **high** — this is the #1 killer of every second-brain | Phase 0 kill signal; no LLM in capture path | D6 |
| Client data reaches the vault | medium | 3 layers + quarantine + history-free intake | D8 |
| Distillation silently loses facts | medium | no-net-loss gate, proposals not auto-apply | D7 |
| Vault becomes write-only (nothing reads it) | medium | success metric is a *read-side* measure, baselined Phase 1, re-measured Phase 3 | §1 |
| Index creep / source-of-truth drift | low (deferred) | D4 trigger conditions + index gitignored | D4 |
| Scope pull toward enterprise before v1 works | medium | D10 puts it in a separate track with only two cheap design constraints now | D10 |

---

## 7 · Open items deliberately left open

1. **Filter policy for Gmail** — undecidable until Phase 5; needs a week of
   observation, not a guess.
2. **`daily/` schema** — owned by the Command Core (v7), not by this plan.
   Define at the interface when Phase 3 lands.
3. **Whether `profile/` is a directory or a single file** — trivial, decide
   at seed time based on what the 24 files actually look like.

---

## 8 · First action

`brain-intake` repo + the Shortcut. Nothing else in Phase 0 matters if a
thought can't get in from a phone in five seconds.

---

## Appendix A · Phase 0 build status (2026-08-15)

Built and tested in this session; delivered as `turbo-brain-phase0.tar.gz`.
Nothing has been created on GitHub or on your machine — `bootstrap.sh` is
dry-run by default and refuses to overwrite an existing path.

**Shipped**

| Component | Where | State |
|---|---|---|
| `turbo-brain` CLI (bash) | `turbo-brain/bin/` | doctor, lint, scan-secrets, scan-deny, capture, intake list/rotate, install-hooks, mcp |
| Secret-scan gate (D8 L2) | `lib/secret_scan.py` | 12 rule families, entropy-checked generics, placeholder allowlist, never prints the match |
| Deny gate (D8 L1) | `lib/deny_scan.py` | word-boundary + domain-substring matching, quarantine move |
| Schema lint (D3) | `lib/lint.py` | 10 checks incl. name/stem, uniqueness, provenance tags, wikilink resolution |
| Read-only MCP server | `mcp/brain_mcp.py` | stdio JSON-RPC, 3 tools, `sensitivity`-filtered, rg-backed with pure-python fallback |
| Pre-commit hook | `hooks/pre-commit` | secrets + deny + lint, installed into both repos |
| Vault + intake templates | `*.template/` | schema-valid seed files, `.turbo-brain.toml`, `CLIENTS.deny` skeleton |
| iOS Shortcut build sheet | `docs/SHORTCUT.md` | action-by-action, incl. the exact Contents API call |
| Redaction SOP | `docs/REDACTION.md` | per-repo deletion stories |

Zero runtime dependencies beyond `git` and `python3`. `rg` optional. That is
a requirement, not an accident — a context vault that can't start on a fresh
machine is worse than none.

**Test results: 22/22.** Clean-bootstrap regression covering lint (green +
4 planted defects), secret-scan (AWS id, GitHub token, placeholder
allowlist), deny-scan + quarantine, a real blocked commit, MCP handshake /
tools/list / search / read / path-traversal refusal, sensitivity filtering,
and both rotate paths.

**Two defects found and fixed during the build — both amend D8:**

1. **Quarantine was self-blocking.** The deny gate caught client material,
   moved it to `quarantine/`, and then the pre-commit hook scanned
   `quarantine/` and refused every subsequent commit. Worse, the fix that
   first suggested itself — exempt the directory — would have committed
   client material to a repo. Correct fix: `quarantine/` is **gitignored**.
   Caught material never enters history at all.
2. **`intake rotate` could strand the repo.** A gate failing mid-rewrite left
   `brain-intake` on an unborn orphan branch with `main` already deleted.
   Now: gates run *before* any rewrite, the commit itself is `--no-verify`,
   and an `ERR` trap restores the original branch. Verified by planting a
   secret and confirming history and branch were untouched.

Both were only findable by running it. Neither was visible in the plan.

**Not built (correctly deferred):** distillation waves (Phase 2), adapters
(Phase 3), email dropbox and sweep wave (Phase 4). The `no_net_loss_pct`
gate is configured in `.turbo-brain.toml` but has no implementation until
there is a wave to gate.

**Your next three actions**

1. `./bootstrap.sh` — read the plan output; add `--apply` when it looks right
2. Populate `CLIENTS.deny` **before** the first distill wave — an empty
   deny-list is a no-op gate that looks green
3. Build the Shortcut from `docs/SHORTCUT.md`, then start the 10-capture day

---

## Appendix B · v1.1 spec amendments (2026-08-16)

Second research round: agent-memory ecosystem survey (mem0, Letta, Zep/
Graphiti, basic-memory, claude-mem, Anthropic's own memory tooling, 2025-26
consolidation research), a memory-poisoning threat model built on
demonstrated attacks, and primary-source verification of the capture and
deletion mechanics. Full findings in TURBO-BRAIN-RESEARCH-2.md.

### What the research validated (no change needed)

The core architecture is independently convergent, not idiosyncratic:
basic-memory (3.7k stars), memweave, Letta's MemFS, Anthropic's API memory
tool, and Claude Code auto-memory all landed on **files as source of truth
with any DB as a rebuildable index**. The only dissent found (Zep's
"markdown is not agent memory") is unquantified vendor marketing that
concedes Claude Code, Letta and Manus all ship markdown memory.

**No-LLM-in-the-capture-path got the strongest single piece of evidence in
the survey:** a 32-day production audit of mem0 found 97.8% of 10,134
stored memories were junk — prompt restatements, feedback loops (one
hallucinated fact stored 808 times), and secrets at 2.1% of entries. LLM
extraction at capture time without gates is the best-documented failure in
the field.

The wave cadence matches the field's converged practice (Letta community:
cheap-model dedup often, full reorganization weekly; basic-memory: reflect
daily, defrag weekly) and sleep-time-compute research validates scheduled
background consolidation as a Pareto improvement.

### Amendments adopted

**B1 — Bi-temporal-lite: event dates + supersede-don't-delete.** Git gives
transaction time free; facts gain an optional inline event date, and
contradiction handling is now: append the replacement, mark the loser
`(superseded <date> → ...)`, sweep drops it monthly. The winner of a
current-value conflict is chosen **mechanically (max event date), never by
LLM judgment** — measured LLM conflict-arbitration accuracy fell 75%→61% as
context grew 64K→262K tokens while deterministic latest-wins stayed flat.
mem0's ADD-only v3 is the cautionary tale for skipping this.

**B2 — Recall-loop guard, named gate.** Content whose source is the brain
itself is quarantined at triage, never distilled. This is the mem0
808-copies feedback loop, made impossible instead of unlikely. The MCP
server's read-time preamble doubles as a marker: a capture containing it is
self-evidently a paste of vault output.

**B3 — Injection-shaped facts are a lint error (new check B5).** Memory is
a persistence mechanism for prompt injection — all demonstrated, not
theoretical: SpAIware (ChatGPT memory → standing exfiltration), the Gemini
long-term-memory attack (a poisoned *document being summarized* hijacked
the summarizer — the distiller-as-victim pattern exactly), MINJA (memory
injection via query-only interaction). Facts are now third-person
declaratives with attribution; the linter tripwires on instruction-override
phrases, persona hijacks, agent-directed imperatives, and markdown-image
exfil URLs. Narrow and high-signal by design — a classifier it is not
(published guardrail classifiers are bypassable at up to 100% with adaptive
attacks; this is a tripwire in a layered defense).

**B4 — Minimum-privilege distiller, specified now for Phase 2.** The
distillation wave is the single most attackable component. Its contract:
model-API access **only** (no WebFetch, no MCP, no shell — deletes the
exfiltration leg of the lethal trifecta); reads intake only; writes to a
**staging branch, never main** — vault main is branch-protected and **you
merge the PR**. Every gate runs as deterministic code on the diff, outside
the LLM. Added: an **additions cap** alongside no-net-loss — the
demonstrated attack class poisons by *adding* few records, not deleting
many (AgentPoison: ≥80% retrieval success at <0.1% poison rate), so a wave
adding anomalously many facts, or facts containing URLs/tool names, gets
flagged not merged. Net effect: a hijacked distiller degrades from
"standing injection against every future session" to "one reviewable bad
diff."

**B5 — Always-loaded INDEX.md, hard-capped (new lint check F7).** One index
file, ≤200 lines / 25 KB — Anthropic's own operating point for Claude Code
auto-memory — loaded first by any reader; everything else just-in-time.
Enforced by lint, not convention.

**B6 — Capture path corrections (verified against primary docs).**
Shortcuts does **not** auto-retry — the Shortcut now carries a 3× retry
loop and a failure path that copies the capture to the clipboard so nothing
is lost silently. Filename collisions 422 safely (no overwrite); near-
simultaneous captures can 409 on the branch-ref race (GitHub does not
serialize ref updates) — covered by the same retry. Fine-grained PATs may
now be no-expiry, but the token stays on 90-day expiry deliberately: it
lives in plaintext in an iCloud-synced Shortcut with no Keychain access,
and expiry is the only mitigation that works without noticing a theft.

**B7 — Server-side gate on intake.** GitHub secret scanning / push
protection is **not available on private personal-plan repos**, and the
phone path bypasses pre-commit entirely — so the intake repo now ships a
gitleaks Actions workflow that scans every push and opens an alarm issue on
a finding. This was the only uncovered gap in the capture path.

**B8 — Retrieval trigger rebalanced.** The 200-candidate-line trigger is
the well-supported one — published evidence says what degrades at scale is
LLM discrimination over the candidate set, not grep. The 3 MB corpus
trigger is demoted to a backstop, and a third trigger is added: observed
vocabulary-miss rate (grep's real failure mode, mitigated meanwhile by
`aliases:`). Instrument from day one so the index decision fires on data.

### Deferred, with reasons

- **Trust-tiered retrieval scoring** (weighting [stated] over [ingested] at
  read time): research shows calibration is the hard part; the provenance
  tags already carry the information and the recipes tool instructs readers
  on precedence. Revisit if a poisoning near-miss ever occurs.
- **Datamarking of ingested spans**: effective on frontier models, measured
  zero benefit on small ones; the declarative-fact rule (B3) achieves the
  robust version of the same goal semantically rather than syntactically.
- **Relay server for the PAT** (Cloudflare Worker holding the token):
  strictly better security, one more moving part; not justified while the
  blast radius is intake-only.
