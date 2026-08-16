---
name: rust-tooling
description: Rust tooling preferences and knowledge
sources: [stated]
sensitivity: shareable
---
- [stated] Prefers cargo over make for Rust projects
- [stated] Uses clap for CLI argument parsing
- [stated] tokio for async runtime, not async-std
- [stated] serde + serde_json for serialization
- [stated] tracing over log for diagnostics
- [stated] criterion for benchmarks, not hand-rolled
- [stated] Avoids unsafe unless the performance win is measured and necessary
- Related: [[profile]]
