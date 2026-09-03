# Turbo Flow v4.0

<div align="center">

![Version](https://img.shields.io/badge/version-4.0.0-blue?style=for-the-badge)
![Ruflo](https://img.shields.io/badge/Ruflo-v3.5-purple?style=for-the-badge)
![MCP Tools](https://img.shields.io/badge/MCP_Tools-215+-green?style=for-the-badge)
![Plugins](https://img.shields.io/badge/Plugins-6-critical?style=for-the-badge)
![License](https://img.shields.io/badge/license-MIT-orange?style=for-the-badge)
![Adventure Wave Labs](https://img.shields.io/badge/Adventure_Wave_Labs-Builder-ff6b6b?style=for-the-badge)

**Complete Agentic Development Environment — Ruflo v3.5 + Beads + Worktrees + Agent Teams**

*Built & Presented by [Adventure Wave Labs](https://www.adventureonthewave.com/#projects)*

[Quick Start](#-quick-start) • [Installation](#-what-gets-installed) • [Plugins](#-plugins-6) • [Commands](#️-key-commands) • [Migration](#-migrating-from-v3x) • [Resources](#-resources)

</div>

---

## 🎬 Demo

![Turbo Flow demo](https://raw.githubusercontent.com/marcuspat/marcuspat/main/demos/turbo-flow-demo.gif)

A real, unedited run of the full onboarding chain — `codespace_setup.sh` →
`setup.sh` → `post-setup.sh` → `tmux-workspace.sh` (11 install steps, 6-plugin
verify: Claude Code, Ruflo v3.5, Dolt + Beads, GitNexus, OpenSpec) — sped up,
then a real reattach to the live tmux session it creates: a tour through all
four workspace windows (`Claude-2`, `Claude-Monitor`, a live `htop`), then the
real `claude` CLI launched through to its actual login screen. Not a mockup,
not a scripted animation — no API key on the recording box, so that's the
genuine first-run auth screen. Recorded with
[VHS](https://github.com/charmbracelet/vhs) from `demo/demo-a-setup.tape` +
`demo/demo-b-tmux-claude.tape` (`demo/build-demo.sh` reproduces it end to end).

---

## About Adventure Wave Labs

<div align="center">
  <img src="https://raw.githubusercontent.com/adventurewave-labs/.github/main/profile/AWLabs.webp" alt="Adventure Wave Labs" width="600">
</div>

**Adventure Wave Labs** is the team behind Turbo Flow, a complete agentic development environment built for the Claude ecosystem. We design, build, and maintain the packaging, setup automation, plugin curation, and workflow integration that brings together orchestration, memory, codebase intelligence, and agent isolation into a single streamlined install. The orchestration core itself — the 215+ MCP tools and 60+ agents referenced throughout this README — is [Ruflo](https://github.com/ruvnet/ruflo) v3.5, built by [ruvnet](https://github.com/ruvnet) ("rUv"); Turbo Flow integrates and configures it rather than building it from scratch.

---

## What's New in v4.0.0

| Metric | v3.4.1 | v4.0.0 | Change |
|--------|--------|--------|--------|
| Installation Steps | 15 | **10** | -5 (consolidated) |
| Core Packages | 4 separate | **1 (Ruflo)** | -75% |
| MCP Tools | 175+ | **215+** | +23% |
| Agents | 60+ | **60+** | — |
| Plugins | 15 | **6** | -9 (redundant removed) |
| Cross-session Memory | None | **Beads** | New |
| Agent Isolation | None | **Git Worktrees** | New |
| Codebase Graph | None | **GitNexus** | New |
| UI/UX Skill | Yes | **Yes** | Kept |
| Statusline | Yes | **Yes** | Updated to 4.0 |

### Major Changes

- **claude-flow → Ruflo v3.5** — Single `npx ruflo@latest init` replaces 4 separate installs
- **Beads** — Cross-session project memory via git-native JSONL
- **GitNexus** — Codebase knowledge graph with MCP server and blast-radius detection
- **Native Git Worktrees** — Per-agent isolation with auto PG Vector schema namespacing
- **Native Agent Teams** — Anthropic's experimental multi-agent spawning
- **6 focused plugins** — 9 redundant/domain-specific plugins removed
- **OpenSpec** — Spec-driven development kept
- **UI UX Pro Max** — Design skill kept
- **Statusline Pro v4.0** — Updated with TF 4.0 branding

### Removed (redundant with Ruflo v3.5 or out of scope)

- `claude-flow@alpha`, `@ruvector/cli`, `@ruvector/sona`, `@claude-flow/browser` → bundled in Ruflo
- 9 plugins: healthcare-clinical, financial-risk, legal-contracts, cognitive-kernel, hyperbolic-reasoning, quantum-optimizer, neural-coordination, prime-radiant, ruvector-upstream
- Claudish, Agentic Jujutsu, Spec-Kit, agtrace, PAL MCP → bundled or redundant
- HeroUI + Tailwind + TypeScript scaffold → out of scope
- Ars Contexta, OpenClaw Secure Stack → out of scope

---

## Architecture

```
+------------------------------------------------------------------+
|               TURBO FLOW v4.0 — Adventure Wave Labs               |
+------------------------------------------------------------------+
|  INTERFACE                                                        |
|  +---------------+  +---------------+  +---------------+          |
|  | Claude Code   |  |  Open WebUI   |  |  Statusline   |          |
|  |     CLI       |  |  (4 instances)|  |   Pro v4.0    |          |
|  +---------------+  +---------------+  +---------------+          |
+------------------------------------------------------------------+
|  ORCHESTRATION: Ruflo v3.5                                        |
|  60+ Agents | 215+ MCP Tools | Auto-activated Skills              |
|  AgentDB v3 | RuVector WASM | SONA | 3-Tier Model Routing        |
|  59 MCP Browser Tools | Observability | Gating                    |
+------------------------------------------------------------------+
|  PLUGINS (6)                                                      |
|  +--------------------------------------------------------------+ |
|  | Agentic QE | Code Intel | Test Intel | Perf | Teammate | Gas | |
|  +--------------------------------------------------------------+ |
+------------------------------------------------------------------+
|  CODEBASE INTELLIGENCE: GitNexus                                  |
|  Knowledge Graph | Blast Radius Detection | MCP Server            |
+------------------------------------------------------------------+
|  MEMORY (Three-Tier)                                              |
|  +---------------+  +---------------+  +---------------+          |
|  |    Beads      |  | Native Tasks  |  |   AgentDB     |          |
|  |  project/git  |  |   session     |  |  + RuVector   |          |
|  |    JSONL      |  |  ~/.claude/   |  |  WASM accel   |          |
|  +---------------+  +---------------+  +---------------+          |
+------------------------------------------------------------------+
|  ISOLATION                                                        |
|  Git Worktrees per Agent | PG Vector Schema per Worktree          |
|  Auto GitNexus Indexing | Agent Teams (experimental)              |
+------------------------------------------------------------------+
|  SKILLS                                                           |
|  UI UX Pro Max | OpenSpec | 36+ Ruflo Auto-activated Skills       |
+------------------------------------------------------------------+
|  INFRASTRUCTURE                                                   |
|  DevPod | Codespaces | Rackspace Spot                            |
+------------------------------------------------------------------+
```

---

## Quick Start

### DevPod Installation

<details>
<summary><b>macOS</b></summary>

```bash
brew install loft-sh/devpod/devpod
```
</details>

<details>
<summary><b>Windows</b></summary>

```bash
choco install devpod
```
</details>

<details>
<summary><b>Linux</b></summary>

```bash
curl -L -o devpod "https://github.com/loft-sh/devpod/releases/latest/download/devpod-linux-amd64"
sudo install devpod /usr/local/bin
```
</details>

### Launch

```bash
# DevPod (recommended)
devpod up https://github.com/marcuspat/turbo-flow --ide vscode

# Codespaces
# Push to GitHub → Open in Codespace → runs automatically

# Manual
git clone https://github.com/marcuspat/turbo-flow -b main
cd turbo-flow
chmod +x devpods/setup.sh
./devpods/setup.sh
source ~/.bashrc
turbo-status
```

---

## What Gets Installed

The `devpods/setup.sh` script installs the complete stack in **10 automated steps**:

### Step 1: System Prerequisites

| Package | Purpose |
|:--------|:--------|
| `build-essential` | C/C++ compiler (gcc, g++, make) |
| `python3` | Python runtime |
| `git` | Version control |
| `curl` | HTTP client |
| `jq` | JSON processor (required for statusline) |
| `Node.js 20+` | JavaScript runtime (required by Ruflo v3.5) |

### Step 2: Claude Code + Ruflo v3.5

| Component | Purpose |
|:----------|:--------|
| `Claude Code` | Anthropic's agentic coding CLI |
| `Ruflo v3.5` | Orchestration engine — replaces claude-flow@alpha |
| Ruflo MCP | Registered as MCP server in Claude Code |
| Ruflo Doctor | Auto-diagnostic and fix pass |

> Ruflo v3.5 bundles: AgentDB v3, RuVector WASM, SONA, 215 MCP tools, 60+ agents, skills system, 3-tier model routing, 59 browser automation MCP tools, observability, gating

### Step 3: Ruflo Plugins (6) + OpenSpec

| Plugin | Purpose |
|:-------|:--------|
| **Agentic QE** | 58 QE agents — TDD, coverage, security scanning, chaos engineering |
| **Code Intelligence** | Code analysis, pattern detection, refactoring suggestions |
| **Test Intelligence** | Test generation, gap analysis, flaky test detection |
| **Perf Optimizer** | Performance profiling, bottleneck detection |
| **Teammate Plugin** | Bridges Native Agent Teams with Ruflo swarms (21 MCP tools) |
| **Gastown Bridge** | WASM-accelerated orchestration, Beads sync (20 MCP tools) |
| **OpenSpec** | Spec-driven development (independent npm package) |

### Step 4: UI UX Pro Max Skill

| Component | Purpose |
|:----------|:--------|
| `uipro-cli` | Design system skill — component patterns, accessibility, responsive layouts, design tokens |

### Step 5: GitNexus (Codebase Knowledge Graph)

| Component | Purpose |
|:----------|:--------|
| `GitNexus` | Indexes dependencies, call chains, execution flows |
| GitNexus MCP | Registered as MCP server — blast-radius detection |

### Step 6: Beads (Cross-Session Memory)

| Component | Purpose |
|:----------|:--------|
| `@beads/bd` | Git-native JSONL project memory — issues, decisions, blockers |

### Step 7: Workspace + Agent Teams

| Component | Purpose |
|:----------|:--------|
| Directories | `src/` `tests/` `docs/` `scripts/` `config/` `plans/` |
| Agent Teams | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` enabled |

### Step 8: Statusline Pro v4.0

3-line statusline with 15 components:

```
LINE 1: [Project] name | [Model] Sonnet | [Git] branch | [TF] 4.0 | [SID] abc123
LINE 2: [Tokens] 50k/200k | [Ctx] #######--- 65% | [Cache] 42% | [Cost] $1.23 | [Time] 5m
LINE 3: [+150] [-50] | [READY]
```

### Step 9: CLAUDE.md Generation

Generates workspace context file with:
- 3-tier memory protocol (Beads → Native Tasks → AgentDB)
- Isolation rules (one worktree per agent)
- Agent Teams rules (max 3 teammates, recursion depth 2)
- Model routing tiers (Opus/Sonnet/Haiku)
- Plugin reference
- Cost guardrails ($15/hr)

### Step 10: Aliases + Environment + MCP Registration

50+ aliases across families: `rf-*`, `ruv-*`, `mem-*`, `bd-*`, `wt-*`, `gnx-*`, `aqe-*`, `os-*`, `hooks-*`, `neural-*`, `turbo-status`, `turbo-help`

---

## Plugins (6)

| Plugin | MCP Tools | Purpose |
|:-------|:----------|:--------|
| **Agentic QE** | 16 | 58 QE agents, TDD, coverage, security, chaos engineering |
| **Code Intelligence** | — | Code analysis, patterns, refactoring |
| **Test Intelligence** | — | Test generation, gaps, flaky tests |
| **Perf Optimizer** | — | Profiling, bottlenecks, optimization |
| **Teammate Plugin** | 21 | Agent Teams ↔ Ruflo swarms bridge, semantic routing |
| **Gastown Bridge** | 20 | WASM orchestration, Beads sync, convoys |

### Removed Plugins (9)

| Plugin | Reason |
|:-------|:-------|
| healthcare-clinical | Domain-specific (HIPAA/FHIR) — not needed |
| financial-risk | Domain-specific (PCI-DSS/SOX) — not needed |
| legal-contracts | Domain-specific — not needed |
| cognitive-kernel | Redundant with Ruflo's neural system |
| hyperbolic-reasoning | Redundant with RuVector WASM hyperbolic embeddings |
| quantum-optimizer | Redundant with Ruflo's EWC++ and RVFOptimizer |
| neural-coordination | Redundant with Ruflo's swarm coordination |
| prime-radiant | Niche — mathematical interpretability |
| ruvector-upstream | Redundant — RuVector bundled in Ruflo v3.5 |

---

## Key Commands

<details>
<summary><b>Status & Help</b></summary>

```bash
turbo-status         # Check all components
turbo-help           # Complete command reference
rf-doctor            # Ruflo health check
rf-plugins           # List installed plugins
```
</details>

<details>
<summary><b>Orchestration (Ruflo)</b></summary>

```bash
rf-wizard            # Interactive setup
rf-swarm             # Hierarchical swarm (8 agents max)
rf-mesh              # Mesh swarm
rf-ring              # Ring swarm
rf-star              # Star swarm
rf-spawn coder       # Spawn a coder agent
rf-daemon            # Start background workers
rf-status            # Ruflo status
```
</details>

<details>
<summary><b>Memory</b></summary>

```bash
bd-ready             # Check project state (session start)
bd-add               # Record issue/decision/blocker
bd-list              # List beads
ruv-remember K V     # Store in AgentDB
ruv-recall Q         # Query AgentDB
mem-search Q         # Search ruflo memory
mem-stats            # Memory statistics
```
</details>

<details>
<summary><b>Isolation</b></summary>

```bash
wt-add agent-1       # Create worktree for agent
wt-remove agent-1    # Clean up worktree
wt-list              # Show all worktrees
wt-clean             # Prune stale worktrees
```
</details>

<details>
<summary><b>Quality & Testing</b></summary>

```bash
aqe-generate         # Generate tests (Agentic QE plugin)
aqe-gate             # Quality gate
os-init              # Initialize OpenSpec in project
os                   # Run OpenSpec
```
</details>

<details>
<summary><b>Intelligence</b></summary>

```bash
hooks-train          # Deep pretrain on codebase
hooks-route          # Route task to optimal agent
neural-train         # Train neural patterns
neural-patterns      # View learned patterns
gnx-analyze          # Index repo into knowledge graph
gnx-serve            # Start local server for web UI
gnx-wiki             # Generate repo wiki from graph
```
</details>

---

## Migrating from v3.x

1. Your old `cf-*` aliases are gone — use `rf-*` instead
2. Slash commands (`/sparc`, etc.) are gone — Ruflo auto-activates skills
3. Run `bd init` in your project repos to enable Beads memory
4. Run `npx gitnexus analyze` in your repos to build the knowledge graph
5. The `v3/` directory preserves everything — nothing was deleted

| v3.4.1 | v4.0.0 |
|:-------|:-------|
| `cf-init` | `rf-init` |
| `cf-swarm` | `rf-swarm` |
| `cf-doctor` | `rf-doctor` |
| `cf-mcp` | Automatic via `rf-wizard` |
| `mem-search` | `mem-search` (unchanged) |
| `cfb-open` | Via Ruflo's bundled browser MCP tools |
| No cross-session memory | `bd-ready`, `bd-add` |
| No isolation | `wt-add`, `wt-remove` |
| No codebase graph | `gnx-analyze` |

---

## Repository Structure

```
turbo-flow/
├── V2/                          ← current versioned release
├── devpods/
│   ├── setup.sh                 ← main setup script
│   ├── post-setup.sh            ← post-setup verification
│   └── devcontainer_files/      ← devcontainer context files
├── CLAUDE.md                    ← workspace context (active)
└── README.md
```

---

## Post-Setup

```bash
# 1. Reload shell
source ~/.bashrc

# 2. Verify installation
turbo-status

# 3. Get help
turbo-help

# 4. Run post-setup verification (13 checks)
# ./devpods/post-setup.sh
```

---

## Version History

| Version | Date | Changes |
|:--------|:-----|:--------|
| **v4.0.0** | Mar 2026 | **Ruflo Migration**: Ruflo v3.5, Beads, GitNexus, Worktrees, Agent Teams, 6 plugins, UI UX Pro Max, OpenSpec |
| v3.4.1 | Feb 2025 | Fixes: skill install removed, plugins command, npm fallback |
| v3.4.0 | Feb 2025 | Complete + Plugins: 36 skills, 15 plugins |
| v3.3.0 | Feb 2025 | Complete installation: 41 skills, memory, MCP |
| v3.0.0 | Feb 2025 | Initial release with Claude Flow V3 |

---

## Resources

| Resource | Link |
|:---------|:-----|
| Adventure Wave Labs | [GitHub: adventurewave-labs](https://github.com/adventurewave-labs) |
| Turbo Flow | [GitHub: marcuspat/turbo-flow](https://github.com/marcuspat/turbo-flow) |
| Ruflo | [GitHub: ruvnet/ruflo](https://github.com/ruvnet/ruflo) |
| RuVector | [GitHub: ruvnet/RuVector](https://github.com/ruvnet/RuVector) |
| ruVLLM | [crates.io: ruvllm](https://crates.io/crates/ruvllm) |
| MetaHarness | [GitHub: ruvnet/agent-harness-generator](https://github.com/ruvnet/agent-harness-generator) |
| Skygraph (optional) | [GitHub: ruvnet/skygraph](https://github.com/ruvnet/skygraph) |
| OpenSpec | [npm: @fission-ai/openspec](https://npmjs.com/package/@fission-ai/openspec) |
| Agentic QE | [npm: agentic-qe](https://npmjs.com/package/agentic-qe) |

---

## License

MIT — Copyright (c) 2025-2026 Adventure Wave Labs

---

<div align="center">

**Built & Presented by Adventure Wave Labs**

*Turbo Flow v4.0 — Ruflo v3.5. 215+ MCP tools. 6 plugins. Beads. GitNexus. Worktrees. One command.*

</div>
https://github.com/marcuspat/turbo-flow/blob/main/AWLabs.png

## Ecosystem

Built with and powers these tools — star the ones you use:

| Repo | What it does |
|------|-------------|
| [**codescope**](https://github.com/adventurewave-labs/codescope) | Single-binary code-intelligence engine for AI agents — no cloud, no DB, no Python |
| [**secret-scan**](https://github.com/adventurewave-labs/secret-scan) | Rust secret scanner — obfuscation detection, up to ~1,200 files/sec measured |
| [**Sentinel**](https://github.com/marcuspat/Sentinel) | Deny-by-default agentic sysadmin: Investigate → Plan → Approve → Act in Rust |
| [**netrain**](https://github.com/marcuspat/netrain) | Matrix-style network monitor in Rust |

## Stay Connected

If Turbo Flow ships value for you, follow [@marcuspat](https://github.com/marcuspat) on GitHub — agentic tooling, Rust crates, and open-source infra drop regularly.

[![Follow @marcuspat](https://img.shields.io/github/followers/marcuspat?label=Follow%20%40marcuspat&style=social)](https://github.com/marcuspat)
