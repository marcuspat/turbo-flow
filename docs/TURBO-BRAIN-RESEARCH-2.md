# Turbo Brain — Research Round 2

2026-08-16 · ecosystem survey + threat model + primary-source verification ·
produces the v1.1 amendments in TURBO-BRAIN-PLAN.md Appendix B

Three parallel investigations: the agent-memory ecosystem beyond ruvnet,
memory poisoning as an attack class, and verification of the capture and
deletion mechanics against GitHub's and Apple's documentation.

---

## 1 · Ecosystem survey — the architecture is convergent, not contrarian

Files-as-source-of-truth with any database as a rebuildable index is now the
shipped consensus: **basic-memory** (markdown + rebuildable SQLite, 3.7k
stars — the closest architecture to ours, stable), **memweave**, **Letta's
MemFS** (git-backed memory filesystem — MemGPT's own lineage drifted to
files-in-git), **Anthropic's API memory tool** (plain files, `str_replace`
editing where the old text is the version token), and **Claude Code
auto-memory** (capped MEMORY.md index + on-demand topic files). The one
dissenting piece — Zep's "markdown is not agent memory" — names failure
modes without a single quantified threshold and concedes in its own text
that Claude Code, Letta and Manus ship markdown memory.

### The mem0 audit — the strongest evidence in the survey

A 32-day production audit (mem0 issue #4573): 10,134 memories, **97.8%
junk**. System-prompt restatements 52.7%, heartbeat noise 11.5%, transient
task state 7.4%, hallucinated profiles 5.2%, **secrets 2.1%**. One
hallucinated "prefers Vim" stored **808 times** through a recall loop —
recalled memories re-extracted and re-stored. Better models made it worse.
Separately, mem0 v3 regressed to ADD-only extraction, so contradictory
facts now coexist with no recency signal (issues #4956, #5867).

Three direct consequences for us: the no-LLM capture path is validated by
the best-documented failure in the field; the **recall-loop guard** becomes
a named gate (B2); and contradiction handling needs a mechanical answer
(B1), because "the extractor will sort it out" demonstrably doesn't.

### Freshness is not an LLM job

The most useful paper found (arXiv 2606.01435): LLM conflict-arbitration
accuracy fell **75% → 61%** as context grew 64K → 262K tokens, while a
deterministic pipeline (retrieve → LLM matches semantically → **max(serial)
picks the winner**) held at 82%. Combined with Graphiti's
invalidate-don't-delete edge model, this produced amendment B1:
optional inline event dates, supersession markers, latest-wins resolved by
comparison, never by judgment.

### Other lessons taken

Letta's community practice: cheap model for consolidation, dedup often,
reorganize weekly, expire by **reference count not age** ("decisions never
expire"). basic-memory's maintenance skills: raw captures immutable, merge
don't append, ~300-line file split threshold, uncertain deletions become
`(review needed)` tags. claude-mem: progressive disclosure read path (tiny
index → drill down) — our recipes tool made concrete; also a cautionary
daemon. Anthropic's implicit recommendations: hard-capped always-loaded
surface (200 lines / 25 KB — adopted as lint F7), machine-stamped
freshness, mechanical gates over model judgment ("Claude usually refuses,
but guarantee it with your handler").

Per-fact provenance in markdown has one shipped precedent:
**open-second-brain** uses `operator-stated > inferred > deduced` with an
explicit precedence rule and mechanical enforcement — near-isomorphic to
`[stated]/[ingested]/[derived]`, which is encouraging in both directions.

### The retrieval-trigger question

No rigorous published threshold for when grep-based retrieval degrades. The
quantified result reframes it: **what degrades is LLM discrimination over
the candidate set, not grep** (75%→61% above). One production anecdote puts
flat *file-choice* breakdown at 200–500 documents without structure;
directory structure + capped index + recipes is the mitigation. Verdict:
the 200-candidate-line trigger is the load-bearing one, 3 MB demoted to
backstop, and a third trigger added — observed vocabulary-miss rate, grep's
actual failure mode ("auth" misses "authentication"), mitigated meanwhile
by `aliases:`.

---

## 2 · Threat model — memory poisoning is demonstrated, not theoretical

The attack class we worried about is real and published:

- **AgentPoison** (NeurIPS 2024): ≥80% retrieval success poisoning <0.1%
  of a memory store. Few records dominate retrieval — which is why the new
  additions cap watches *small* anomalies, not just bulk changes.
- **Gemini long-term memory attack** (Rehberger 2025): a poisoned document
  *being summarized* hijacked the summarizer into planting a delayed memory
  write. This is the distiller-as-victim pattern — our distillation wave,
  exactly.
- **SpAIware** (2024): injected ChatGPT-memory instructions exfiltrated
  every future conversation. Memory converts one injection into a standing
  one.
- **MINJA** (2025): memory injection through query-only interaction — no
  write access needed.
- **EchoLeak** (CVE-2025-32711) and the **GitHub MCP toxic flow** show the
  damage leg: exfil via auto-rendered markdown images and via agents that
  combine private data + untrusted content + write-capable tools (the
  lethal trifecta).

What holds up per published evaluation, not vendor claims: capability
confinement (CaMeL-style — untrusted data never gains control flow or tool
access) and human review of memory writes are the only strong controls;
spotlighting/datamarking is real but model-dependent (halves ASR on Claude
Haiku, zero on Llama 3.1 8B); write-time classifiers are bypassable at up
to 100% with adaptive attacks (hence B5 is a tripwire, not a gate); read-
time reminders are cheap and weak (added anyway, as depth).

Result: the **minimum-privilege distiller contract** (B4). Model-API only,
intake-read only, staging-branch writes, human merge, deterministic gates
on the diff, additions cap. The honest claim: the distiller cannot be made
injection-proof — no published defense achieves that on any benchmark — but
its compromise becomes non-persistent, non-exfiltrating, and detectable.
"Standing injection against every future session" collapses to "one
reviewable bad diff."

Also from this thread: facts as third-person declaratives with attribution
(store *"Priya said the deadline moved"*, never the verbatim command text),
lint-enforced (B3/B5); and the trifecta audit — any session that reads the
vault AND holds network + GitHub-write tools is the highest-risk
configuration in the architecture. That is worth knowing about your Cowork
sessions generally.

---

## 3 · Primary-source verification — three corrections

**Shortcuts does not auto-retry.** The SHORTCUT.md claim "Shortcuts
retries" was wrong: a failed network action throws and halts; from an
automation you may see only a notification. Corrected: the Shortcut carries
its own 3× retry loop keyed on status 201, and the failure path copies the
capture text to the clipboard. Related verified mechanics: a filename
collision returns 422 and cannot overwrite (no `sha` sent → create-only);
two near-simultaneous captures can 409 because GitHub does **not**
serialize branch-ref updates; rate limits are 1–2 orders of magnitude away
from a personal workload.

**"History-free" was an over-claim.** A force-push (including the orphan
rotate) makes old commits unreachable from refs, but on GitHub they remain
**fetchable by SHA indefinitely** — cached views and API access survive,
and there is no automatic server-side GC; purging requires a support
ticket. Corrected everywhere to "history-free locally, history-hidden on
the remote," with a documented escalation: delete+recreate the repo bounds
the tail at GitHub's 90-day restore window. Practical exposure remains low
(private, no forks, no PRs — SHA-fishing needs the SHAs).

**No server-side secret backstop exists on a personal plan.** GitHub secret
scanning and push protection are unavailable on private personal-plan
repos, and the phone capture path bypasses pre-commit entirely — meaning
the intake repo had an uncovered gap. Closed by B7: a gitleaks GitHub
Actions workflow in the intake repo scans every push server-side and opens
an alarm issue on a finding.

Also verified: fine-grained PATs may now be no-expiry (Oct 2024 change) —
we keep 90-day expiry deliberately, because the token lives in plaintext in
an iCloud-synced Shortcut with no Keychain access; Contents:write grants
nothing beyond Contents + mandatory Metadata-read; deploy keys cannot do
API writes; a GitHub App is infeasible from Shortcuts without a relay.

---

## 4 · Scorecard against the existing spec

| Decision | Research verdict |
|---|---|
| D1 plain files in git | **Validated** — five independent systems converged on it |
| D3 schema + provenance tags | **Validated + extended** — precedent exists (open-second-brain); B1/B3 refine it |
| D4 no index in v1 | **Validated** — triggers rebalanced (B8) |
| D6 no-LLM capture | **Validated** by the mem0 audit — the strongest evidence found |
| D6 Shortcut mechanics | **Corrected** — retry + failure path added (B6) |
| D7 waves + budgets | **Validated** — matches field practice; additions cap added (B4) |
| D8 gates | **Extended** — B5 lint, recall-loop guard, server-side intake gate (B7) |
| D8 deletion story | **Corrected** — history-hidden, not history-free; escalation documented |

Nothing in either research round contradicted a core decision. Every
correction was in a claim about *someone else's system behavior* (Shortcuts
retry, GitHub GC) — the decisions themselves held. The two genuine gaps
found across both rounds: per-fact time/supersession, and the entire
injection-persistence threat class. Both are now in the spec and the lint.
