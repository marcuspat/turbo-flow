# Turbo Brain

> Local-first personal knowledge vault using plain markdown in git.

Turbo Brain is a **zero-dependency** (Python stdlib only) knowledge vault with:

- **Schema-linted markdown** — every fact carries provenance tags and must pass structural gates
- **Secret scanning** — blocks API keys, tokens, connection strings before they enter the vault
- **Client deny-list** — prevents client material from leaking into personal knowledge
- **Agent-poison tripwires** — injection-shaped facts are caught by narrow, high-signal regex patterns
- **Bi-temporal provenance** — every fact is `[stated]`, `[ingested]`, or `[derived]` with source citations
- **stdio MCP server** — read/search/capture tools for AI agent integration
- **Bash CLI** — `turbo-brain doctor`, `lint`, `capture`, `selftest`, `mcp`, and more
- **Wave runner** — scheduled triage / distill / sweep pipelines with budget gates
- **Next.js dashboard** — vault browser, search, capture form, doctor status, wave history

## Architecture

```
brain-intake/          brain-vault/
├── inbox/             ├── profile/     # who you are
│   └── *.md           ├── areas/       # ongoing involvements
├── ledger/            ├── people/      # relationship context
└── quarantine/        ├── projects/    # per-repo distillate
                      ├── topics/      # domain facts
                      ├── daily/       # day state
                      ├── INDEX.md     # always-loaded index (capped)
                      └── CLIENTS.deny # client deny-list
```

**Capture is pure text PUT** — no LLM in the capture path. The distiller (wave runner) is a separate, minimum-privilege contract that runs on a staging branch with human merge.

## Quick Start

```bash
# Clone
 git clone git@github.com:adventurewave-labs/turbo-brain.git
 cd turbo-brain

# Initialize vault + intake repos
 mkdir -p ~/brain-vault ~/brain-intake
 cd ~/brain-vault && git init
 cd ~/brain-intake && git init

# Install the CLI
 export PATH="$PWD/bin:$PATH"
 export TB_ROOT="$PWD"

# Check environment
 turbo-brain doctor

# Run selftest (negative controls prove gates fire)
 turbo-brain selftest

# Capture a fact
 turbo-brain capture "decided to use bun over npm for new projects"

# Install pre-commit gates
 turbo-brain install-hooks
```

## Gate Pipeline (D8)

Every commit to the vault runs:

1. **Secret scan** (Layer 2) — regex-based, entropy-gated, never prints values
2. **Deny scan** (Layer 1) — CLIENTS.deny enforcement
3. **Schema lint** (D3) — frontmatter, fact tags, citation resolution, injection detection

Wave runner adds:
4. **Dedup** — content-identity checks
5. **No-net-loss** — vault can't shrink more than N% per wave
6. **Additions cap** — can't grow more than N% per wave

## MCP Server

```json
{
  "mcpServers": {
    "turbo-brain": {
      "command": "python3",
      "args": ["/path/to/turbo-brain/mcp/brain_mcp.py"],
      "env": {
        "BRAIN_VAULT": "/path/to/brain-vault",
        "BRAIN_MAX_SENSITIVITY": "private"
      }
    }
  }
}
```

Tools: `brain_search`, `brain_read`, `brain_list`, `brain_facts`, `brain_recipes`

## Next.js Dashboard

```bash
cd dashboard
bun install
bun dev
```

Vault browser, search, capture form, doctor status panel, and wave history.

## Threat Model

| Threat | Mitigation |
|--------|-----------|
| AgentPoison (injected facts) | B5 tripwire regexes — narrow, high-signal patterns from demonstrated attacks |
| Distiller as victim | Minimum-privilege contract: model-API only, no shell, intake-read only, staging branch |
| Standing injection | Recall-loop guard (B2): brain content can't be re-ingested without explicit [ingested] tag |
| Secret leakage | D8 L2: regex + entropy scan, never prints matched values |
| Client material spill | D8 L1: CLIENTS.deny with vacuous-pass protection |

## Project Structure

```
turbo-brain/
├── bin/
│   └── turbo-brain          # Bash CLI entrypoint
├── lib/
│   ├── lint.py              # Schema lint (F1-F8, B1-B6, L1-L2)
│   ├── secret_scan.py       # Secret detection gate
│   ├── deny_scan.py         # Client deny-list gate
│   ├── doctor.py            # Vault health check
│   └── wave_runner.py       # Triage/distill/sweep orchestration
├── mcp/
│   └── brain_mcp.py         # Stdio MCP server
├── adapters/
│   └── __init__.py          # BaseAdapter + RunLedgerAdapter
├── hooks/
│   └── pre-commit           # Git pre-commit gate
├── tests/
│   └── test_all.py          # Full test suite
├── dashboard/               # Next.js web dashboard
├── demo/                    # Example vault + intake for testing
└── docs/
    ├── TURBO-BRAIN-PLAN.md
    ├── TURBO-BRAIN-RUVNET-AUDIT.md
    ├── TURBO-BRAIN-RESEARCH-2.md
    └── RUVNET-REUSE-ASSESSMENT.md
```

## License

Private — adventurewave-labs
