# The Ruv Stack — Turbo Flow v4.1.0

Turbo Flow's orchestration core (Ruflo v3.5, RuVector WASM) is already built on
[ruvnet](https://github.com/ruvnet)'s ("rUv") ecosystem. This doc maps the full branded
stack — ruFlo / ruVector / ruVLLM / RuView / Skygraph / PhotonLayer / MetaHarness / rUv
Neural — to the *real* ruvnet repos behind each name, and states plainly which ones are
wired into Turbo Flow, which are optional, and which don't exist.

Every row below was verified against the live ruvnet GitHub org, not assumed from the
branding.

| Name | Real project | Status in Turbo Flow | Why |
|---|---|---|---|
| **ruFlo** | [`ruflo`](https://github.com/ruvnet/ruflo) — agent meta-harness, npm `ruflo` | **Core** (already v3.5) | This *is* Turbo Flow's orchestration engine. Unchanged by this edition. |
| **ruVector** | [`RuVector`](https://github.com/ruvnet/RuVector) — vector+GNN memory DB, Rust/WASM via npm | **Deepened** | Already documented in this repo as optional (`AGENTDB-VS-RUVECTOR.md`) but not installed by default. This edition is the "install it" step for agents that hit AgentDB's ceiling — ML routing, code analysis, 50+ agent coordination. |
| **ruVLLM** | `ruvllm` / `ruvllm-esp32` on [crates.io](https://crates.io/crates/ruvllm), sparse-attention example inside [`RuVector`](https://github.com/ruvnet/RuVector/tree/main/examples/ruvLLM) | **New** | Adds a local/offline model-routing tier — sparse-attention inference you can run without hitting Anthropic's API for cheap, high-volume, or air-gapped tasks. |
| **MetaHarness** | [`agent-harness-generator`](https://github.com/ruvnet/agent-harness-generator), npm `metaharness` | **New** | Generates a branded, per-repo CLI/MCP harness. Genuinely useful across your multi-project workflow (CreandoTuMatrix, AdventureWave, Cargo-Forge, etc.) — one harness-factory instead of hand-rolling tooling per repo. |
| **Skygraph** | [`skygraph`](https://github.com/ruvnet/skygraph) — browser all-sky radar (ADS-B + satellites), Rust/WASM | **Optional stub** | Real, small (15★), and has nothing to do with dev tooling. Documented as an opt-in demo plugin, not wired into the core flow. |
| **RuView** | [`RuView`](https://github.com/ruvnet/RuView) — WiFi CSI spatial sensing (presence/vitals/pose through walls) | **Excluded** | Real and substantial (79k★) but it's a physical-sensing/smart-home platform, not agentic dev tooling. Out of scope for this edition. |
| **rUv Neural** | `ruv-neural-*` crates — EEG/quantum-sensor brain-network topology analysis | **Excluded** | Real research framework, but BCI/cognitive-state decoding has no integration point in a coding harness. Out of scope. |
| **PhotonLayer** | — | **No real repo found** | Not present anywhere in the ruvnet org (297 repos checked) as of this doc's research date. Infographic-only branding. Treated as unconfirmed/roadmap — revisit if `ruvnet/photonlayer` ever ships. |

---

## What's actually wired in

### RuVector (deepened)

This repo already documents the AgentDB-vs-RuVector tradeoff in
[`AGENTDB-VS-RUVECTOR.md`](../AGENTDB-VS-RUVECTOR.md): AgentDB (HNSW-indexed, JS/TS,
auto-installed) handles *what agents remember*; RuVector (optional, npm-distributed
Rust/WASM) handles *how agents learn and route* — Q-learning-based routing, AST
analysis, code risk scoring, graph algorithms. That doc's own guidance is "try
AgentDB first, add RuVector later if needed" — this edition is that "later."

```bash
npm install ruvector
```

Reach for it when you hit one of the triggers `AGENTDB-VS-RUVECTOR.md` already lists:
ML-based agent routing that improves over time, code analysis (complexity metrics,
module boundaries), advanced neural optimization (Flash Attention, SONA, LoRA), or
distributed coordination for 50+ agents. AgentDB and RuVector aren't alternatives —
AgentDB persists outcomes, RuVector learns from them.

### ruVLLM (new — local model tier)

`ruvllm` gives Turbo Flow a fourth model-routing tier below Haiku: a fully local,
sparse-attention model for tasks that don't need any hosted model at all (bulk
formatting, log triage, high-volume classification).

```bash
cargo install ruvllm
# edge/embedded variant:
cargo add ruvllm-esp32
```

Routing tiers become:

```
Opus (architecture)  → Sonnet (implementation) → Haiku (lookups) → ruVLLM (local/offline, $0)
```

Wire it into `hooks-route` decisions by treating `ruvllm` as a candidate for any task
tagged cost-sensitive or offline in your routing config.

### MetaHarness (new — per-repo harness factory)

```bash
npx metaharness
```

Generates a branded CLI + MCP server + scoped memory namespace + governance policy for
a target repo, output as an npm-publishable package. Point it at any of your active
repos (Turbo-Flow itself, Cargo-Forge, Secret-Scan, NetRain) to scaffold a dedicated
agent harness instead of hand-wiring Ruflo config per project. Supports Claude Code,
Codex, Hermes, and GitHub Actions as target hosts.

### Skygraph (optional, off by default)

```bash
git clone https://github.com/ruvnet/skygraph
cd skygraph/docs && python3 -m http.server 8000
```

No build step, no API keys — prebuilt WASM. Not part of `turbo-status` or any core
alias; run it manually if you want it.

---

## Install

```bash
./scripts/setup-ruv-stack.sh          # dry-run plan by default
./scripts/setup-ruv-stack.sh --apply  # actually install
./scripts/setup-ruv-stack.sh --apply --with-skygraph   # include the optional stub
```

See [`scripts/setup-ruv-stack.sh`](../scripts/setup-ruv-stack.sh) for the full,
idempotent installer — it never touches `devpods/setup.sh`; it's a pure add-on that
runs after the standard v4.0 install.

## New aliases (`rv-*`)

| Alias | Command |
|---|---|
| `rv-vector-init` | `npm install ruvector` — the step `AGENTDB-VS-RUVECTOR.md` documents but leaves optional |
| `rv-llm-serve` | Start local `ruvllm` inference server |
| `rv-llm-route` | Route a task to the local ruVLLM tier instead of a hosted model |
| `rv-harness-gen` | `npx metaharness` — scaffold a branded harness for the current repo |
| `rv-sky-demo` | Launch the optional Skygraph local demo (only if installed with `--with-skygraph`) |

Full alias definitions live in `scripts/setup-ruv-stack.sh` and are sourced from
`~/.turboflow_ruv_aliases`, parallel to the existing `~/.turboflow_aliases` from the
v4.0 install — nothing in the original alias file is touched or overridden.
