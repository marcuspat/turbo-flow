# Contributing to Turbo Flow

Thank you for your interest in contributing to Turbo Flow — the portable governance kit ([`rig-lite/`](rig-lite/)) built by [Adventure Wave Labs](https://github.com/adventurewave-labs).

## Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/<your-username>/turbo-flow.git
   cd turbo-flow
   ```
3. Create a feature branch (or a worktree, the kit way: `rig-lite/wt.sh <name>`)
4. Make your changes
5. Prove them: `bash rig-lite/self-test.sh` (fail-closed; must pass)
6. Push and open a pull request against `main` — every PR gets a cross-family review from the gate (`rig-lite/gate.sh --pr <n> --builder <your-cli>`)

## Development Setup

### Prerequisites

- Bash, git, python3 — that's it
- Any coding-agent CLI you like (ZCode, Claude Code, Codex) — none is bundled or required to run the kit
- `shellcheck` on PATH for full self-test coverage (the suite says so when it's missing)

### Quick Setup

```bash
bash rig-lite/self-test.sh          # proves the kit on your machine
bash rig-lite/init-repo.sh          # optional: wire AGENTS.md into any repo you're testing against
```

### Verification

```bash
bash rig-lite/self-test.sh          # the suite every PR must pass
bash rig-lite/gate.sh --base main --builder <cli>   # branch mode: deterministic checks + review
```

## Pull Request Guidelines

- Keep PRs focused — one feature or fix per PR
- Update `README.md` if your change affects the interface or command set
- Reference related issues in the PR description (`Closes #123`)
- Add a changelog entry if it's user-facing

## Reporting Issues

Open a GitHub issue with:
- A clear title and description
- Steps to reproduce
- Expected vs actual behavior
- OS and the output of `bash rig-lite/self-test.sh`

## Security Vulnerabilities

Do not open a public issue for security bugs. See [SECURITY.md](./SECURITY.md) for responsible disclosure.

## License

By contributing, you agree your changes will be licensed under the [MIT License](./LICENSE).
