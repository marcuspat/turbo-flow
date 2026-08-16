---
name: agent-memory-ecosystem
description: landscape of agent memory systems and what works
sources: [seed, ingested]
sensitivity: shareable
---
- [stated] Files-as-source-of-truth with rebuildable index is the converged architecture
- [stated] Five independent systems landed on this: basic-memory, memweave, Letta MemFS, Anthropic API memory, Claude Code auto-memory
- [ingested] mem0 32-day audit: 10,134 memories, 97.8% junk (src: research-2 2026-08-16)
- [ingested] mem0 recall loop: hallucinated 'prefers Vim' stored 808 times (src: research-2 2026-08-16)
- [ingested] mem0 secrets at 2.1% of stored entries (src: research-2 2026-08-16)
- [ingested] LLM conflict-arbitration accuracy fell 75% to 61% as context grew 64K to 262K tokens (src: research-2 2026-08-16)
- [ingested] Deterministic latest-wins held at 82% across all context sizes (src: research-2 2026-08-16)
- [ingested] AgentPoison: 80%+ retrieval success at less than 0.1% poison rate (src: research-2 2026-08-16)
- [ingested] Gemini long-term memory attack: poisoned document hijacked the summarizer (src: research-2 2026-08-16)
- [ingested] SpAIware: injected ChatGPT memory instructions exfiltrated every future conversation (src: research-2 2026-08-16)
- [stated] Retrieval degrades not from grep but from LLM discrimination over the candidate set
- [stated] Published retrieval trigger: 200-500 documents without structure is where flat file-choice breaks down
- [stated] Directory structure plus capped index plus recipes mitigates the retrieval problem
- Related: [[turbo-brain]], [[turbo-flow]]
