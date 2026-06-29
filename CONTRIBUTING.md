# Contributing to Turbo Flow

Thank you for your interest in contributing to Turbo Flow — the advanced agentic development environment built by [Adventure Wave Labs](https://github.com/adventurewave-labs).

## Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/<your-username>/turbo-flow.git
   cd turbo-flow
   ```
3. Create a feature branch:
   ```bash
   git checkout -b feat/your-feature
   ```
4. Make your changes
5. Test your changes (see below)
6. Push and open a pull request against `main`

## Development Setup

### Prerequisites

- Claude Code CLI installed
- DevPod or GitHub Codespaces (recommended)
- Node.js 20+
- Python 3.8+
- Docker (for DevPod-based testing)

### Quick Setup

```bash
chmod +x devpods/setup.sh
./devpods/setup.sh
source ~/.bashrc
turbo-status
```

### Verification

```bash
./devpods/post-setup.sh   # Runs 13 automated checks
turbo-help                 # Lists available commands
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
- OS, DevPod/Codespaces version, and `turbo-status` output

## Security Vulnerabilities

Do not open a public issue for security bugs. See [SECURITY.md](./SECURITY.md) for responsible disclosure.

## License

By contributing, you agree your changes will be licensed under the [MIT License](./LICENSE).
