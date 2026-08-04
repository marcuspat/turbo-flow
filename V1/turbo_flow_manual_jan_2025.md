# TURBO FLOW CLAUDE - COMPLETE USER MANUAL

**Version 1.0.2 Alpha | Bulletproof v9**

*Advanced Agentic Development Environment*

> **Note (Aug 2026):** This is a historical snapshot of this manual as it existed in January 2025 (v1.0.2 Alpha). Some figures below are outdated -- notably the subagent count ("600+"/"610+"), which was later corrected to its accurate figure of 60+. See the current README for up-to-date information.

---

## TABLE OF CONTENTS

1. [Introduction](#1-introduction)
2. [Quick Start](#2-quick-start)
3. [Installation Summary](#3-installation-summary)
4. [Claude Code CLI](#4-claude-code-cli)
5. [Claude Flow Orchestration](#5-claude-flow-orchestration)
6. [SPARC Methodology](#6-sparc-methodology)
7. [610+ AI Subagents](#7-610-ai-subagents)
8. [Agentic Flow](#8-agentic-flow)
9. [Agentic QE (Testing Framework)](#9-agentic-qe-testing-framework)
10. [Agentic Jujutsu (Version Control)](#10-agentic-jujutsu-version-control)
11. [OpenSpec (Spec-Driven Development)](#11-openspec-spec-driven-development)
12. [Spec-Kit](#12-spec-kit)
13. [Claudish (Multi-Model Proxy)](#13-claudish-multi-model-proxy)
14. [AI Agent Skills](#14-ai-agent-skills)
15. [n8n-MCP Server](#15-n8n-mcp-server)
16. [PAL MCP Server](#16-pal-mcp-server)
17. [Playwright MCP](#17-playwright-mcp)
18. [Chrome DevTools MCP](#18-chrome-devtools-mcp)
19. [agtrace (AI Agent Observability)](#19-agtrace-ai-agent-observability)
20. [uv Package Manager](#20-uv-package-manager)
21. [direnv](#21-direnv)
22. [Command Reference](#22-command-reference)
23. [Workflows](#23-workflows)
24. [Troubleshooting](#24-troubleshooting)
25. [Resources](#25-resources)

---

## 1. INTRODUCTION

### What is Turbo Flow Claude?

Turbo Flow Claude is an advanced agentic development environment that combines multiple AI-powered tools into a unified workflow system:

- **600+ AI Agents** for coding, research, and business analysis
- **Claude Flow** - Enterprise AI orchestration with swarm intelligence
- **SPARC Methodology** - Systematic development workflow
- **Multi-Model Support** - Use Claude, GPT, Gemini, and local models together
- **Automatic Context Loading** - Simplified commands with full context
- **Multi-Platform Support** - DevPods, GitHub Codespaces, Google Cloud Shell, Rackspace Spot

### What Gets Installed

The `setup.sh` script installs:

| Category | Tools |
|----------|-------|
| Core AI | Claude Code CLI, Claude Flow |
| Agents | Agentic Flow, Agentic QE, Agentic Jujutsu |
| Specifications | OpenSpec, Spec-Kit |
| Multi-Model | Claudish, PAL MCP Server |
| MCP Servers | Playwright, Chrome DevTools, n8n-MCP |
| Skills | AI Agent Skills, frontend-design, mcp-builder, code-review |
| Utilities | uv, direnv, 610ClaudeSubagents |

---

## 2. QUICK START

### DevPods Installation (Recommended)

```bash
# Install DevPod
# macOS:
brew install loft-sh/devpod/devpod

# Windows:
choco install devpod

# Linux:
curl -L -o devpod "https://github.com/loft-sh/devpod/releases/latest/download/devpod-linux-amd64"
sudo install devpod /usr/local/bin

# Launch Turbo Flow workspace
devpod up https://github.com/marcuspat/turbo-flow-claude --ide vscode
```

### First Commands After Setup

```bash
# Load aliases
source ~/.bashrc

# Start Claude Code
claude

# Or skip permissions for faster iteration
dsp

# Run a swarm task
cf-swarm "build a REST API with authentication"

# Use hive-mind for complex projects
cf-hive "create a full-stack e-commerce app"
```

---

## 3. INSTALLATION SUMMARY

### NPM Global Packages (12)

| Package | Purpose |
|---------|---------|
| `@anthropic-ai/claude-code` | Claude Code CLI |
| `claude-usage-cli` | Usage monitoring and cost tracking |
| `agentic-qe` | AI-powered quality engineering |
| `agentic-flow` | Self-learning agent orchestration |
| `agentic-jujutsu` | AI-enhanced version control |
| `claudish` | Multi-model proxy for Claude Code |
| `@fission-ai/openspec` | Spec-driven development |
| `@playwright/mcp` | Browser automation MCP |
| `chrome-devtools-mcp` | Chrome debugging MCP |
| `mcp-chrome-bridge` | Chrome integration bridge |
| `n8n-mcp` | n8n workflow automation MCP |
| `@lanegrid/agtrace` | AI agent observability |

### Python Tools

| Tool | Purpose |
|------|---------|
| `uv` | Ultra-fast Python package manager |
| `specify-cli` | Spec-Kit CLI for specifications |

### Git-Cloned Repositories

| Repository | Location | Purpose |
|------------|----------|---------|
| `pal-mcp-server` | `~/.pal-mcp-server` | Multi-model AI collaboration |
| `610ClaudeSubagents` | `agents/` | 600+ specialized AI agents |

### Skills Installed

| Skill | Purpose |
|-------|---------|
| `frontend-design` | UI/UX design assistance |
| `mcp-builder` | MCP server development |
| `code-review` | Automated code review |

---

## 4. CLAUDE CODE CLI

### Overview

Claude Code is Anthropic's official AI coding tool that lives in your terminal. It understands your codebase, edits files, runs commands, and handles complete workflows through natural language.

### Installation

```bash
# NPM (installed by setup.sh)
npm install -g @anthropic-ai/claude-code

# Or native binary (recommended for performance)
curl -fsSL https://claude.ai/install.sh | bash
```

### Basic Usage

```bash
# Start Claude Code
claude

# Skip permission prompts (faster iteration)
claude --dangerously-skip-permissions
dsp  # Alias

# Check version
claude --version

# Run diagnostics
claude doctor
```

### Slash Commands (Inside Session)

| Command | Purpose |
|---------|---------|
| `/help` | Show available commands |
| `/agents` | List available subagents |
| `/memory` | Access memory functions |
| `/bug` | Report a bug to Anthropic |
| `/clear` | Clear conversation context |
| `/compact` | Reduce context size |

### Subagents

Subagents are specialized AI assistants defined as markdown files.

**Locations:**
- Project: `.claude/agents/*.md`
- User: `~/.claude/agents/*.md`

**Example Subagent Definition:**

```markdown
---
name: code-reviewer
description: Expert code reviewer focused on best practices
tools: Read, Grep, Glob, Bash
model: sonnet
---

You are a senior code reviewer. Focus on:
- Code quality and readability
- Security vulnerabilities
- Performance optimizations
- Best practices adherence

Always provide actionable feedback with examples.
```

### CLAUDE.md Project File

Create a `CLAUDE.md` file in your project root to give Claude persistent context:

```markdown
# Project: My Application

## Structure
- `src/` - Main application code
- `tests/` - Test suites
- `docs/` - Documentation

## Conventions
- Use TypeScript for all new files
- Follow REST API naming conventions
- Write tests for all new features

## Commands
- `npm run build` - Build the project
- `npm test` - Run tests
- `npm run lint` - Check code style
```

### Workflow: Using Claude Code

```bash
# 1. Navigate to your project
cd my-project

# 2. Start Claude
claude

# 3. Ask Claude to understand your codebase
> "Analyze this codebase and explain its structure"

# 4. Make changes
> "Add error handling to all API endpoints"

# 5. Run tests
> "Run the test suite and fix any failures"

# 6. Commit changes
> "Create a commit with a descriptive message for these changes"
```

---

## 5. CLAUDE FLOW ORCHESTRATION

### Overview

Claude Flow v2.7 is an enterprise-grade AI orchestration platform that enables:
- Multi-agent swarm coordination
- Hive-mind collaborative intelligence
- Persistent memory with semantic search
- 25 auto-activating Claude Skills
- SPARC methodology integration

### Key Features

| Feature | Description |
|---------|-------------|
| Swarm Intelligence | Coordinate multiple AI agents |
| Hive-Mind | Shared knowledge and reasoning |
| ReasoningBank | 2-3ms query memory system |
| AgentDB | 96x-164x faster semantic search |
| SPARC | Built-in TDD workflow |

### Installation & Initialization

```bash
# Initialize in your project (REQUIRED first step)
npx claude-flow@alpha init --force

# Or use the alias
cf-init
```

### Swarm Commands

Swarms are best for quick, focused tasks:

```bash
# Quick task with context
cf-swarm "build REST API with authentication"

# Or full command
npx claude-flow@alpha swarm "analyze this codebase" --claude

# Initialize custom swarm topology
npx claude-flow@alpha swarm init --topology mesh --max-agents 5

# Spawn specific agents
npx claude-flow@alpha swarm spawn researcher "analyze API patterns"
npx claude-flow@alpha swarm spawn coder "implement endpoints"

# Check swarm status
npx claude-flow@alpha swarm status
```

### Hive-Mind Commands

Hive-mind is best for complex, multi-phase projects:

```bash
# Interactive setup wizard
npx claude-flow@alpha hive-mind wizard

# Spawn hive-mind for a project
cf-hive "build enterprise authentication system"

# Or full command with options
npx claude-flow@alpha hive-mind spawn "build microservices" \
  --agents architect,coder,reviewer \
  --namespace backend \
  --claude

# Check status
npx claude-flow@alpha hive-mind status

# Resume a session
npx claude-flow@alpha hive-mind resume session-xxxxx
```

### Memory Commands

```bash
# Store information
npx claude-flow@alpha memory store api_config "REST endpoints at /api/v1" \
  --namespace backend

# Query memory
npx claude-flow@alpha memory query "API configuration" \
  --namespace backend

# Semantic vector search
npx claude-flow@alpha memory vector-search "user authentication flow" \
  --k 10 --threshold 0.7

# List all stored memories
npx claude-flow@alpha memory list --namespace backend

# Check memory status
npx claude-flow@alpha memory status

# Clear memory
npx claude-flow@alpha memory clear --namespace backend
```

### Swarm vs Hive-Mind Decision Guide

| Use Swarm When | Use Hive-Mind When |
|----------------|-------------------|
| Quick, single tasks | Complex, multi-phase projects |
| One-off requests | Ongoing development |
| Simple coordination | Deep collaboration |
| Task < 30 minutes | Project spans days/weeks |
| Limited context needed | Extensive shared knowledge |

### Workflow: Building a Feature with Claude Flow

```bash
# 1. Initialize Claude Flow
cf-init

# 2. Start hive-mind for the feature
cf-hive "implement user authentication with JWT"

# 3. Claude Flow will:
#    - Spawn appropriate agents (architect, coder, tester)
#    - Create implementation plan
#    - Store decisions in memory
#    - Coordinate between agents

# 4. Check progress
npx claude-flow@alpha hive-mind status

# 5. Query what was learned
npx claude-flow@alpha memory query "authentication decisions"

# 6. Continue work in new session
npx claude-flow@alpha hive-mind resume [session-id]
```

---

## 6. SPARC METHODOLOGY

### Overview

SPARC is a systematic development methodology with five phases:

1. **S**pecification - Define requirements and constraints
2. **P**seudocode - Plan logic and data structures
3. **A**rchitecture - Design system structure
4. **R**efinement - TDD (Red-Green-Refactor)
5. **C**ompletion - Integration and deployment

### Available Modes (17)

| Mode | Purpose |
|------|---------|
| `spec-pseudocode` | Requirements and logic planning |
| `architect` | System design |
| `tdd` | Test-driven development |
| `coder` | Implementation |
| `reviewer` | Code review |
| `researcher` | Information gathering |
| `orchestrator` | Task coordination |
| `debugger` | Bug fixing |
| `security` | Security analysis |
| `performance` | Optimization |
| `documentation` | Documentation writing |
| `devops` | Infrastructure and deployment |
| `integration` | System integration |
| `supabase-expert` | Database specialist |
| `cleanup` | Code cleanup |

### Commands

```bash
# Run full TDD workflow
npx claude-flow sparc tdd "user authentication system"

# Run specific phase
npx claude-flow sparc run spec-pseudocode "shopping cart feature"
npx claude-flow sparc run architect "payment processing"
npx claude-flow sparc run coder "implement cart functionality"

# List all available modes
npx claude-flow sparc modes

# Run with specific agents
npx claude-flow sparc run security "analyze authentication code"
```

### Workflow: TDD with SPARC

```bash
# 1. Specification Phase
npx claude-flow sparc run spec-pseudocode "Create a user registration system"
# Output: requirements.md, pseudocode outline

# 2. Architecture Phase
npx claude-flow sparc run architect "Design user registration system"
# Output: architecture diagram, component design

# 3. TDD Phase (Red-Green-Refactor)
npx claude-flow sparc tdd "Implement user registration"
# - Writes failing tests first (Red)
# - Implements minimal code to pass (Green)
# - Cleans up code (Refactor)

# 4. Review Phase
npx claude-flow sparc run reviewer "Review user registration implementation"
# Output: code review with suggestions

# 5. Documentation Phase
npx claude-flow sparc run documentation "Document user registration API"
# Output: API documentation, usage examples
```

---

## 7. 610+ AI SUBAGENTS

### Overview

The 610ClaudeSubagents collection provides specialized AI agents for virtually any task:

- **422 Non-Coding Agents**: Business, research, personal, predictions
- **188 Coding Agents**: Development, testing, infrastructure, security

### Agent Categories

#### Coding Agents (188)

| Category | Examples |
|----------|----------|
| Frontend | React, Vue, Angular, Svelte experts |
| Backend | Node.js, Python, Java, Go specialists |
| Database | SQL, NoSQL, GraphQL masters |
| DevOps | Docker, Kubernetes, CI/CD pros |
| Security | Penetration testing, audit specialists |
| Testing | Unit, integration, E2E experts |
| Mobile | iOS, Android, React Native |
| Cloud | AWS, GCP, Azure specialists |

#### Non-Coding Agents (422)

| Category | Examples |
|----------|----------|
| Business Analysis | Market research, competitor analysis |
| Financial | Investment analysis, forecasting |
| Personal Development | Career coaching, learning paths |
| Content Creation | Blog writing, copywriting |
| Project Management | Agile coaching, sprint planning |
| Legal | Contract review, compliance |
| HR/Recruiting | Job descriptions, interview prep |
| Data Analysis | Statistical analysis, visualization |

### Language & Framework Experts

| Category | Expertise |
|----------|-----------|
| Languages | Python, JavaScript, TypeScript, Rust, Go, Java, C#, PHP, Ruby, Swift, Kotlin |
| Frontend | React 19, Next.js 15, Angular, Vue.js, Svelte |
| Backend | Django, Flask, Spring Boot, Laravel, Rails, Express |
| Data | Pandas, NumPy, TensorFlow, PyTorch |

### Using Agents

```bash
# List available agents
ls agents/*.md | head -20

# Search for specific agents
find agents/ -name "*react*"
find agents/ -name "*security*"
find agents/ -name "*market*"

# Use with Claude Flow swarm
cf-swarm "First discover agents with 'find agents/ -name \"*game*\"' then build space invaders"

# Use specific agent in Claude Code
claude
> "Use the @agent-react-expert to build a dashboard component"
```

### Example Workflows

#### Market Research Workflow

```bash
cf-swarm "Research sustainable fashion market for Gen Z using:
- market-user-research agent for consumer insights
- competitor-benchmarking-agent for market analysis  
- trend-detection-agent for future predictions
Create a comprehensive report."
```

#### Full-Stack Development Workflow

```bash
cf-hive "Build an e-commerce platform using:
- react-expert for frontend
- node-backend-expert for API
- postgresql-expert for database
- devops-specialist for deployment
Follow TDD methodology."
```

---

## 8. AGENTIC FLOW

### Overview

Agentic Flow v2.0 provides self-learning AI agents that improve with experience:

- **66 Specialized Agents** with adaptive learning
- **213 MCP Tools** for comprehensive capabilities
- **+55% Quality Improvement** through learning
- **<1ms Learning Overhead** with SONA integration
- **60% Cost Savings** via intelligent model routing

### Installation

```bash
# Installed by setup.sh
npm install -g agentic-flow@alpha
```

### Commands

```bash
# Basic command
af "analyze this codebase for performance issues"

# Run with specific agent
af-run --agent coder "implement user authentication"

# Use coder agent specifically
af-coder "create a REST API endpoint"

# Get help
af-help
```

### Agent Types

| Agent | Specialization |
|-------|---------------|
| Coder | Code generation and implementation |
| Researcher | Information gathering and analysis |
| Architect | System design and planning |
| Reviewer | Code review and quality assurance |
| Debugger | Bug identification and fixing |
| Documenter | Documentation writing |
| Tester | Test creation and execution |

### Workflow: Self-Learning Development

```bash
# 1. Start with a task
af "build a user authentication system"

# 2. Agentic Flow learns from the process:
#    - Records successful patterns
#    - Tracks what works
#    - Improves future recommendations

# 3. Next similar task benefits from learning
af "build an admin authentication system"
# Uses patterns learned from previous auth implementation

# 4. Check learning status
npx agentic-flow status --learning
```

---

## 9. AGENTIC QE (TESTING FRAMEWORK)

### Overview

Agentic QE (Quality Engineering) Fleet is an AI-powered testing platform:

- **19 Main Agents** for different QE tasks
- **11 TDD Subagents** for test-driven development
- **40 QE Skills** covering testing methodologies
- **Real-time Visualization** of test results
- **Flaky Test Detection** and automatic remediation

### Installation

```bash
# Installed by setup.sh
npm install -g agentic-qe

# Initialize in your project
aqe init

# Add MCP server to Claude Code
claude mcp add agentic-qe npx aqe-mcp
```

### Commands

```bash
# Initialize AQE in project
aqe init

# Generate tests
aqe generate tests src/services/user-service.ts

# Run tests with AI analysis
aqe run --analyze

# Detect flaky tests
aqe flaky-hunt --runs 100

# Quality gate check
aqe quality-gate --coverage 95
```

### Using with Claude Code

```bash
# Start Claude
claude

# Generate comprehensive tests
> "Use qe-test-generator to create tests for src/services/user-service.ts with 95% coverage"

# Run quality pipeline
> "Initialize AQE fleet: generate tests, execute them, analyze coverage, and run quality gate"

# Hunt for flaky tests
> "Use qe-flaky-test-hunter to analyze the last 100 test runs and identify flaky tests"
```

### QE Agents

| Agent | Purpose |
|-------|---------|
| `qe-test-generator` | Generate comprehensive tests |
| `qe-test-executor` | Run tests in parallel |
| `qe-coverage-analyzer` | Analyze test coverage |
| `qe-quality-gate` | Validate quality thresholds |
| `qe-flaky-test-hunter` | Identify flaky tests |
| `qe-performance-tester` | Performance testing |
| `qe-security-scanner` | Security testing |

### Workflow: Quality Engineering Pipeline

```bash
# 1. Initialize AQE
aqe init

# 2. Generate tests for your services
claude "Use qe-test-generator to create tests for src/services/*.ts"

# 3. Run tests in parallel
claude "Use qe-test-executor to run all tests in parallel"

# 4. Analyze coverage
claude "Use qe-coverage-analyzer to find gaps with 95% target"

# 5. Run quality gate
claude "Use qe-quality-gate to validate against 95% threshold"

# 6. Hunt flaky tests
claude "Use qe-flaky-test-hunter to analyze and fix flaky tests"
```

---

## 10. AGENTIC JUJUTSU (VERSION CONTROL)

### Overview

Agentic Jujutsu brings Jujutsu VCS to AI agents with:

- **Embedded jj Binary** - No separate installation needed
- **Self-Learning** - Learns from your git patterns
- **Lock-Free Operations** - 23x faster than Git
- **Multi-Agent Support** - Multiple agents work simultaneously
- **Automatic Conflict Resolution** - 87% success rate

### Why Jujutsu Over Git?

| Feature | Git | Jujutsu |
|---------|-----|---------|
| Working Copy | Requires staging | Auto-commits |
| Undo | Complex reflog | Simple `jj undo` |
| Conflicts | Block workflow | First-class citizens |
| Multi-Agent | Requires worktrees | Native support |
| Learning | None | Patterns tracked |

### Installation

```bash
# Installed by setup.sh
npm install -g agentic-jujutsu
```

### Commands

```bash
# Check status
jj-agent status

# Analyze repository
jj-agent analyze

# Compare with git
jj-agent compare-git

# MCP tools
npx agentic-jujutsu mcp-tools
npx agentic-jujutsu mcp-server
```

### JavaScript API

```javascript
const { JjWrapper } = require('agentic-jujutsu');
const jj = new JjWrapper();

// Basic operations
await jj.status();
await jj.newCommit('Add feature');
await jj.log(10);

// Self-learning trajectory
const id = jj.startTrajectory('Implement authentication');
await jj.branchCreate('feature/auth');
await jj.newCommit('Add auth');
jj.addToTrajectory();
jj.finalizeTrajectory(0.9, 'Clean implementation');

// Get AI suggestions
const suggestion = JSON.parse(jj.getSuggestion('Add logout feature'));
console.log(`Confidence: ${suggestion.confidence}`);
```

### Workflow: AI-Driven Version Control

```bash
# 1. Initialize repository
jj-agent init

# 2. Work on feature (auto-commits)
# Edit files... jj automatically tracks changes

# 3. Describe changes
jj describe -m "Add user authentication"

# 4. Create branch
jj-agent branch-create feature/auth

# 5. If mistake, easy undo
jj undo

# 6. View operation history
jj op log

# 7. Push to remote
jj git push
```

---

## 11. OPENSPEC (SPEC-DRIVEN DEVELOPMENT)

### Overview

OpenSpec provides spec-driven development (SDD) for AI coding assistants:

- **Spec Before Code** - Lock intent before implementation
- **Change Tracking** - Proposals, tasks, and spec deltas
- **Multi-Tool Support** - Works with Claude Code, Cursor, Codex, etc.
- **Slash Commands** - Quick access to OpenSpec operations

### Installation

```bash
# Installed by setup.sh
npm install -g @fission-ai/openspec
```

### Commands

```bash
# Initialize OpenSpec in your project
openspec init

# List change proposals
openspec list

# Show a specific change
openspec show add-user-auth

# Validate a change proposal
openspec validate add-user-auth

# Archive completed change
openspec archive add-user-auth

# Update tool configurations
openspec update
```

### Directory Structure

```
project/
├── openspec/
│   ├── project.md           # Project conventions
│   ├── specs/               # Current truth (source of truth)
│   │   └── auth/
│   │       └── spec.md
│   └── changes/             # Proposed updates
│       └── add-oauth/
│           ├── proposal.md
│           ├── tasks.md
│           └── specs/
│               └── auth/
│                   └── spec.md
└── AGENTS.md                # Auto-generated for AI tools
```

### Slash Commands (In Claude Code)

| Command | Purpose |
|---------|---------|
| `/openspec:proposal` | Create new change proposal |
| `/openspec:apply` | Apply a change proposal |
| `/openspec:validate` | Validate spec formatting |
| `/openspec:archive` | Archive completed change |

### Workflow: Spec-Driven Development

```bash
# 1. Initialize OpenSpec
openspec init

# 2. Start Claude Code
claude

# 3. Create a proposal
> "Create an OpenSpec change proposal for adding OAuth authentication"
# Or use: /openspec:proposal Add OAuth authentication

# 4. Review and iterate
openspec show add-oauth
> "Add acceptance criteria for Google and GitHub OAuth providers"

# 5. Apply the change
> "Apply the add-oauth change proposal"
# Or use: /openspec:apply add-oauth

# 6. Archive when complete
openspec archive add-oauth
```

### Best Practices

1. **Always start with a proposal** - Don't code without specs
2. **Keep specs focused** - One feature per change folder
3. **Iterate on specs first** - Get agreement before implementation
4. **Use tasks.md** - Break work into trackable tasks
5. **Archive after completion** - Keep history clean

---

## 12. SPEC-KIT

### Overview

Spec-Kit is GitHub's specification management tool that helps maintain project specifications and documentation.

### Installation

```bash
# Installed by setup.sh via uv
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
```

### Commands

```bash
# Initialize in current directory
specify init .

# Initialize with Claude AI support
sk-here  # Alias for: specify init . --ai claude

# Check specification health
specify check

# Generate CLAUDE.md from specs
generate-claude-md
```

### Workflow: Setting Up Spec-Kit

```bash
# 1. Initialize Spec-Kit
sk-here

# 2. Generate CLAUDE.md from specifications
generate-claude-md

# 3. Start Claude with project context
claude

# 4. Use Spec-Kit slash commands
> /speckit.constitution    # View project constitution
> /speckit.specify         # Create specifications
> /speckit.plan           # Generate project plan
> /speckit.tasks          # List tasks
> /speckit.implement      # Begin implementation
```

### Directory Structure

```
project/
├── .specify/
│   ├── constitution.md    # Project rules and guidelines
│   ├── specs/             # Feature specifications
│   ├── plan.md           # Implementation plan
│   └── tasks/            # Individual tasks
└── CLAUDE.md             # Generated project context
```

---

## 13. CLAUDISH (MULTI-MODEL PROXY)

### Overview

Claudish allows you to run Claude Code with any AI model by proxying requests:

- **100+ Models** via OpenRouter
- **Direct API Access** - Google Gemini, OpenAI
- **Local Models** - Ollama, LM Studio, vLLM
- **Thinking Translation** - Handles different model capabilities
- **Multi-Instance** - Run multiple models in parallel

### Installation

```bash
# Installed by setup.sh
npm install -g claudish
```

### Setup

```bash
# Set API key
export OPENROUTER_API_KEY='sk-or-v1-...'

# Optional: Set default model
export CLAUDISH_MODEL='x-ai/grok-code-fast-1'
```

### Commands

```bash
# Interactive mode (prompts for setup)
claudish

# With specific model
claudish --model x-ai/grok-code-fast-1 "fix the bug in user.ts"

# List available models
claudish --models

# Search for models
claudish --models gemini
claudish --models "grok code"

# Show top recommended models
claudish --top-models
```

### Popular Models

| Model | Best For |
|-------|----------|
| `x-ai/grok-code-fast-1` | Fast coding, visible reasoning |
| `google/gemini-2.5-flash` | Quick tasks, good balance |
| `openai/gpt-5-codex` | Complex refactoring |
| `qwen/qwen3-vl-235b` | UI/visual tasks |

### Workflow: Multi-Model Development

```bash
# Terminal 1: Use Grok for fast coding
claudish --model x-ai/grok-code-fast-1 "add error handling"

# Terminal 2: Use GPT-5 for complex tasks
claudish --model openai/gpt-5-codex "refactor entire API layer"

# Terminal 3: Use Gemini for code review
git diff | claudish --stdin --model google/gemini-2.5-flash "review changes"

# Compare models on same task
for model in "x-ai/grok-code-fast-1" "google/gemini-2.5-flash"; do
  echo "=== Testing with $model ==="
  claudish --model "$model" "find security vulnerabilities in auth.ts"
done
```

---

## 14. AI AGENT SKILLS

### Overview

AI Agent Skills is the universal skill repository for AI coding agents:

- **38+ Curated Skills** - Quality over quantity
- **9+ Compatible Agents** - Claude Code, Cursor, Amp, VS Code, Copilot, Goose, Letta, OpenCode
- **One Command Install** - Works everywhere automatically
- **Open Standard** - Based on Anthropic's Agent Skills specification

### Installation

```bash
# Installed by setup.sh
npm install -g ai-agent-skills

# Install a skill for Claude Code (default)
npx ai-agent-skills install frontend-design

# Install for other agents
npx ai-agent-skills install frontend-design --agent cursor
npx ai-agent-skills install frontend-design --agent amp
npx ai-agent-skills install frontend-design --agent vscode
```

### CLI Commands

```bash
# List all available skills
npx ai-agent-skills list

# Search for skills
npx ai-agent-skills search <query>

# Get skill details
npx ai-agent-skills info <skill-name>

# Install a skill
npx ai-agent-skills install <skill-name>

# Install for specific agent
npx ai-agent-skills install <skill-name> --agent <agent>
```

### Supported Agents

| Agent | Flag | Install Location |
|-------|------|------------------|
| Claude Code | `--agent claude` (default) | `~/.claude/skills/` |
| Cursor | `--agent cursor` | `.cursor/skills/` |
| Amp | `--agent amp` | `~/.amp/skills/` |
| VS Code / Copilot | `--agent vscode` | `.github/skills/` |
| Goose | `--agent goose` | `~/.config/goose/skills/` |
| OpenCode | `--agent opencode` | `~/.opencode/skills/` |
| Portable | `--agent project` | `.skills/` (works with any) |

### Available Skills by Category

**Development:**
| Skill | Description |
|-------|-------------|
| `frontend-design` | Production-grade UI components and styling |
| `mcp-builder` | Create MCP servers for agent tool integrations |
| `skill-creator` | Guide for creating new agent skills |
| `code-review` | Automated PR review patterns |
| `code-refactoring` | Systematic code improvement techniques |
| `backend-development` | APIs, databases, server architecture |
| `python-development` | Modern Python 3.12+ patterns |
| `javascript-typescript` | ES6+, Node, React, TypeScript |
| `webapp-testing` | Browser automation with Playwright |
| `database-design` | Schema design and optimization |
| `llm-application-dev` | Build LLM-powered applications |
| `artifacts-builder` | Interactive React/Tailwind components |
| `changelog-generator` | Generate changelogs from git commits |

**Documents:**
| Skill | Description |
|-------|-------------|
| `pdf` | Extract, create, merge, split PDFs |
| `xlsx` | Excel creation, formulas, data analysis |
| `docx` | Word documents with formatting |
| `pptx` | PowerPoint presentations |

**Creative:**
| Skill | Description |
|-------|-------------|
| `canvas-design` | Visual art and poster creation |
| `algorithmic-art` | Generative art with p5.js |
| `image-enhancer` | Improve image quality and resolution |
| `slack-gif-creator` | Create animated GIFs for Slack |
| `theme-factory` | Professional font and color themes |
| `video-downloader` | Download videos from platforms |

**Business:**
| Skill | Description |
|-------|-------------|
| `brand-guidelines` | Apply brand colors and typography |
| `internal-comms` | Status updates and team communication |
| `competitive-ads-extractor` | Analyze competitor ad strategies |
| `domain-name-brainstormer` | Generate and check domain availability |
| `lead-research-assistant` | Identify and qualify leads |

**Productivity:**
| Skill | Description |
|-------|-------------|
| `job-application` | Cover letters using your CV |
| `qa-regression` | Automated regression testing |
| `jira-issues` | Create, update, search Jira issues |
| `code-documentation` | Generate docs from code |
| `content-research-writer` | Research and write with citations |
| `file-organizer` | Organize files and find duplicates |
| `invoice-organizer` | Organize invoices for tax prep |
| `meeting-insights-analyzer` | Analyze meeting transcripts |

### Skill Structure

A skill is a folder following the Agent Skills spec:

```
my-skill/
├── SKILL.md       # Instructions + metadata (required)
├── scripts/       # Optional automation scripts
└── references/    # Optional documentation
```

### SKILL.md Format

```yaml
---
name: my-skill
description: What this skill does
version: 1.0.0
author: Your Name
tags: [category1, category2]
---

# My Skill

Instructions for the AI agent on how to use this skill...
```

### Pre-Installed Skills (Turbo Flow)

These skills are installed by setup.sh:

| Skill | Purpose |
|-------|---------|
| `frontend-design` | High-quality UI/UX development |
| `mcp-builder` | Create MCP server integrations |
| `code-review` | Automated code review patterns |

### Manual Installation

```bash
# Clone the repository
git clone https://github.com/skillcreatorai/Ai-Agent-Skills.git

# Copy a skill manually
cp -r Ai-Agent-Skills/skills/pdf ~/.claude/skills/
```

### Creating Custom Skills

**Option 1: AI-Generated (30 seconds)**
Visit [skillcreator.ai/build](https://skillcreator.ai/build)

**Option 2: Manual Creation**
Follow the [Agent Skills spec](https://agentskills.io/specification)

### Workflow: Installing Skills for a Project

```bash
# 1. List available skills
npx ai-agent-skills list

# 2. Search for relevant skills
npx ai-agent-skills search "testing"

# 3. Get skill details
npx ai-agent-skills info webapp-testing

# 4. Install the skill
npx ai-agent-skills install webapp-testing

# 5. Verify installation
ls ~/.claude/skills/
```

### Resources

| Resource | URL |
|----------|-----|
| Browse Skills | [skillcreator.ai/explore](https://skillcreator.ai/explore) |
| Create Skills | [skillcreator.ai/build](https://skillcreator.ai/build) |
| Specification | [agentskills.io](https://agentskills.io) |
| GitHub Repo | [github.com/skillcreatorai/Ai-Agent-Skills](https://github.com/skillcreatorai/Ai-Agent-Skills) |
| Awesome List | [Awesome-Agent-Skills](https://github.com/skillcreatorai/Awesome-Agent-Skills) |

---

## 15. N8N-MCP SERVER

### Overview

n8n-MCP provides Claude with comprehensive knowledge of n8n's 545+ workflow automation nodes:

- **543 Node Types** with full documentation
- **Real-World Examples** - 2,646 configurations from templates
- **Config Validation** - Validate before deployment
- **AI Workflow Validation** - For AI Agent workflows

### Installation

```bash
# Installed by setup.sh
npm install -g n8n-mcp

# Register with Claude
claude mcp add n8n-mcp npx -y n8n-mcp
```

### Features

| Feature | Description |
|---------|-------------|
| Smart Node Search | Find nodes by name, category, or function |
| Essential Properties | Get the 10-20 properties that matter |
| Real Examples | 2,646 pre-extracted configurations |
| Config Validation | Validate before deployment |

### Usage with Claude

```bash
# Start Claude
claude

# Ask about n8n nodes
> "What n8n nodes can send Slack messages?"

# Build a workflow
> "Create an n8n workflow that monitors a webhook and sends alerts to Slack"

# Validate configuration
> "Validate this n8n workflow configuration for errors"
```

### Workflow: Building n8n Automations

```bash
# 1. Start Claude with n8n-MCP
claude

# 2. Describe your automation
> "I need to:
   - Watch a Google Sheet for new rows
   - Process the data
   - Send results to Slack
   Build the n8n workflow."

# 3. Claude uses n8n-MCP to:
#    - Find correct node types
#    - Get exact property names
#    - Provide working configuration
#    - Validate the workflow

# 4. Export and import to n8n
```

---

## 16. PAL MCP SERVER

### Overview

PAL (Provider Abstraction Layer) MCP enables multi-model AI collaboration:

- **Multiple Models in One Prompt** - Gemini, GPT, Claude, Grok, Ollama
- **Conversation Threading** - Context flows across models
- **CLI Subagents** - Launch isolated CLI instances
- **Context Revival** - Recover from context resets

### Installation

```bash
# Cloned by setup.sh to ~/.pal-mcp-server
cd ~/.pal-mcp-server

# Setup (handles everything)
./run-server.sh

# Or setup with uv
uv sync
```

### Configuration

Create `.env` file:

```bash
# Required - at least one provider
GEMINI_API_KEY=your-gemini-key
OPENAI_API_KEY=your-openai-key

# Optional
ANTHROPIC_API_KEY=your-claude-key
GROK_API_KEY=your-grok-key

# Settings
DEFAULT_MODEL=auto
MAX_CONVERSATION_TURNS=20
CONVERSATION_TIMEOUT_HOURS=3
```

### Usage Patterns

```bash
# Start Claude with PAL
claude

# Multi-model code review
> "Perform a code review using gemini pro and o3, then use planner 
   to generate fixes, implement them, and do a final precommit check"

# Get second opinion
> "Analyze this architecture with Gemini, then get O3's perspective"

# Context revival (after reset)
> "Continue our discussion with Gemini"
# PAL revives the full conversation history
```

### Workflow: Multi-Model Development

```bash
# 1. Setup PAL
pal-setup

# 2. Start Claude
claude

# 3. Complex workflow with multiple models
> "Think hard about designing a calculator app in Swift.
   Review your design with O3, taking their suggestions.
   Begin implementing.
   Get code review from Gemini Pro.
   Chat with Flash for creative directions."

# 4. PAL orchestrates:
#    - Claude does initial design
#    - O3 reviews design decisions
#    - Claude implements
#    - Gemini Pro reviews code
#    - Flash provides creative input

# 5. Context preserved across all models
```

---

## 17. PLAYWRIGHT MCP

### Overview

Playwright MCP (by Microsoft) enables browser automation through structured accessibility snapshots:

- **LLM-Friendly** - Uses accessibility tree, not screenshots
- **Cross-Browser** - Chrome, Firefox, WebKit, Edge
- **Device Emulation** - 143+ devices (iPhone, iPad, Pixel, etc.)
- **Fast & Lightweight** - No vision models needed
- **Deterministic** - Structured data avoids screenshot ambiguity

### Key Features

| Feature | Description |
|---------|-------------|
| Accessibility Snapshots | Interact via structured data, not pixels |
| Auto Browser Install | Downloads browsers on first use |
| Device Emulation | Test on 143+ device profiles |
| Network Control | Block/allow specific origins |
| Headless/Headed | Run visible or hidden |
| Session Persistence | Maintain login state |

### Installation

```bash
# Installed by setup.sh
npm install -g @playwright/mcp

# Register with Claude
claude mcp add playwright npx -y @playwright/mcp@latest

# Install browser binaries (auto-installed on first use)
npx playwright install
npx playwright install chromium
npx playwright install firefox
npx playwright install webkit
```

### CLI Options

```bash
npx @playwright/mcp@latest --help

# Common options:
--browser <browser>       # chrome, firefox, webkit, msedge
--device <device>         # "iPhone 15", "iPad Pro", etc.
--headless               # Run without visible browser
--viewport-size <size>   # "1280x720"
--user-agent <ua>        # Custom user agent
--timeout-action <ms>    # Action timeout (default: 5000)
--timeout-navigation <ms> # Navigation timeout (default: 60000)
--caps <caps>            # Enable: vision, pdf
--blocked-origins <list> # Block specific origins
--allowed-origins <list> # Allow specific origins
```

### MCP Configuration

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"]
    }
  }
}
```

### Usage with Claude

```bash
# Start Claude
claude

# Navigate and interact
> "Open https://example.com and take a screenshot"

# Form automation  
> "Fill out the login form with test credentials"

# Device testing
> "Test on iPhone 15 and take a screenshot"

# Multi-browser testing
> "Test the checkout flow on Chrome, Firefox, and Safari"
```

### Available Tools

| Tool | Purpose |
|------|---------|
| `navigate` | Go to URL |
| `click` | Click elements |
| `fill` | Type into inputs |
| `screenshot` | Capture page |
| `get_text` | Extract text content |
| `evaluate` | Run JavaScript |
| `wait_for` | Wait for elements |
| `resize` | Change viewport/device |

### Workflow: Cross-Browser Testing

```bash
# 1. Start Claude
claude

# 2. Test on multiple browsers
> "Navigate to our app and test the login flow on:
   - Chrome desktop
   - Firefox 
   - Safari (WebKit)
   - iPhone 15 (mobile)
   Take screenshots of each and report any differences"

# 3. Form testing
> "Fill out the registration form with test data and submit.
   Verify the success message appears."

# 4. Visual regression
> "Take screenshots of the dashboard on desktop and mobile.
   Compare layouts and report any responsive issues."
```

### Workflow: E2E Testing Pipeline

```bash
# 1. Start Claude
claude

# 2. Complete user flow test
> "Test the complete e-commerce flow:
   1. Navigate to the homepage
   2. Search for 'laptop'
   3. Add first result to cart
   4. Go to checkout
   5. Fill shipping form
   6. Verify order summary
   Take screenshots at each step."
```

---

## 18. CHROME DEVTOOLS MCP

### Overview

Chrome DevTools MCP (official from Chrome team) gives AI assistants full DevTools access:

- **Performance Insights** - Record traces, analyze LCP, CLS, FID
- **Advanced Debugging** - Network requests, console, DOM
- **Reliable Automation** - Built on Puppeteer with auto-wait
- **Live Inspection** - Query and modify page state

### Key Features

| Feature | Description |
|---------|-------------|
| Performance Traces | Record and analyze page performance |
| Network Monitoring | Track all requests/responses |
| Console Access | View logs, errors, warnings |
| DOM Inspection | Query and manipulate elements |
| JavaScript Evaluation | Execute code in page context |
| Emulation | CPU throttling, network speed, viewport |

### Installation

```bash
# Installed by setup.sh
npm install -g chrome-devtools-mcp

# Register with Claude
claude mcp add chrome-devtools npx chrome-devtools-mcp@latest
```

### CLI Options

```bash
npx chrome-devtools-mcp@latest --help

# Connection options:
--browserUrl, -u         # Connect to running Chrome (http://127.0.0.1:9222)
--wsEndpoint, -w         # WebSocket endpoint
--autoConnect           # Auto-connect to Chrome 145+
--channel               # Chrome channel: stable, beta, dev, canary
--headless              # Run headless

# Browser options:
--userDataDir           # Profile directory
--windowSize            # Window dimensions
--enableGpu             # Enable GPU acceleration
```

### MCP Configuration

```json
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["chrome-devtools-mcp@latest"]
    }
  }
}
```

### Available Tools (24+)

**Navigation & Interaction:**
| Tool | Purpose |
|------|---------|
| `navigate_page` | Go to URL |
| `click` | Click elements |
| `fill` | Type into inputs |
| `drag` | Drag and drop |
| `hover` | Hover over elements |
| `take_screenshot` | Capture page |

**Debugging:**
| Tool | Purpose |
|------|---------|
| `list_console_messages` | Get console output |
| `list_network_requests` | View network activity |
| `evaluate_javascript` | Run JS in page |
| `get_page_info` | Page title, URL, etc. |

**Performance:**
| Tool | Purpose |
|------|---------|
| `performance_start_trace` | Begin recording |
| `performance_stop_trace` | End and analyze |
| `get_performance_metrics` | LCP, CLS, FID scores |

**Emulation:**
| Tool | Purpose |
|------|---------|
| `emulate_cpu` | CPU throttling |
| `emulate_network` | Simulate slow connections |
| `resize_page` | Change viewport |

### Usage with Claude

```bash
# Start Claude
claude

# Performance analysis
> "Check the LCP score for https://example.com"

# Debug console errors
> "Navigate to our app and list any console errors"

# Network analysis
> "Monitor network requests when loading the dashboard
   and identify any failed requests"

# JavaScript debugging
> "Evaluate document.querySelectorAll('button').length
   on the current page"
```

### Workflow: Performance Optimization

```bash
# 1. Start Claude
claude

# 2. Get performance baseline
> "Navigate to https://mysite.com and run a performance trace.
   Report LCP, CLS, and total blocking time."

# 3. Identify issues
> "List the slowest network requests and largest resources"

# 4. Test improvements
> "Emulate a slow 3G connection and check how the page performs"

# 5. Get recommendations
> "Based on the performance trace, what are the top 3 things
   I should fix to improve load time?"
```

### Workflow: Debugging Session

```bash
# 1. Start Claude
claude

# 2. Navigate and inspect
> "Go to our staging site and check for any console errors"

# 3. Network debugging
> "List all failed network requests (4xx and 5xx errors)"

# 4. DOM inspection
> "Run JavaScript to count how many images don't have alt text"

# 5. Fix verification
> "After I deploy the fix, recheck for console errors"
```

### Connecting to Existing Chrome

```bash
# Start Chrome with debugging port
google-chrome --remote-debugging-port=9222

# Or on macOS
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=9222

# Configure MCP to connect
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["chrome-devtools-mcp@latest", "--browserUrl", "http://127.0.0.1:9222"]
    }
  }
}
```

---

## 19. AGTRACE (AI AGENT OBSERVABILITY)

### Overview

agtrace provides local-first observability for AI coding agents:

- **Zero Instrumentation** - Auto-discovers provider logs
- **100% Local** - Privacy by design, no cloud dependencies
- **Universal Timeline** - Unified view across all providers
- **MCP Integration** - Agents can query their own history
- **Live Dashboard** - Real-time TUI monitoring

### Supported Providers

| Provider | Description |
|----------|-------------|
| Claude Code | Anthropic's coding agent |
| Codex | OpenAI's coding agent |
| Gemini CLI | Google's coding agent |

### Installation

```bash
# Installed by setup.sh
npm install -g @lanegrid/agtrace

# Initialize workspace (one-time)
cd my-project
agtrace init

# Launch live dashboard
agtrace watch
```

### CLI Commands

```bash
# Live monitoring
agtrace watch              # Real-time TUI dashboard

# Session management
agtrace session list       # Browse session history
agtrace session show <id>  # View specific session

# Search and analysis
agtrace lab grep "error"   # Search across sessions
agtrace lab grep "tool"    # Find tool calls
```

### MCP Integration

Let your AI agent query its own execution history:

**Claude Code:**
```bash
claude mcp add agtrace -- agtrace mcp serve
```

**Codex (OpenAI):**
```bash
codex mcp add agtrace -- agtrace mcp serve
```

**Claude Desktop Configuration:**
```json
{
  "mcpServers": {
    "agtrace": {
      "command": "agtrace",
      "args": ["mcp", "serve"]
    }
  }
}
```

### What Agents Can Query

Once MCP is connected, your agent can:

- **Search past sessions** for tool calls and errors
- **Retrieve tool results** from previous work
- **Analyze failure patterns** across sessions
- **Track token usage** and costs

### Example Agent Queries

```
"Show me sessions with failures in the last hour"
"Search for tool calls that modified the database schema"
"Analyze the most recent session for performance issues"
"Find all bash commands I ran yesterday"
"Show me my token usage this week"
```

### Dashboard Features

The `agtrace watch` TUI dashboard shows:

| Panel | Information |
|-------|-------------|
| Context Window | Current usage and pressure |
| Activity Timeline | Tool calls and responses |
| Token Usage | Input/output token counts |
| Cost Tracking | Estimated API costs |
| Error Log | Recent errors and warnings |

### Workflow: Debugging Agent Sessions

```bash
# 1. Start monitoring
agtrace watch

# 2. In another terminal, run your agent
claude

# 3. Watch real-time activity in the dashboard
# See tool calls, token usage, errors as they happen

# 4. After session, search history
agtrace lab grep "error"
agtrace session list
```

### Workflow: Agent Self-Reflection

```bash
# 1. Add MCP to Claude Code
claude mcp add agtrace -- agtrace mcp serve

# 2. Start Claude
claude

# 3. Ask agent to analyze its own history
> "Search my recent sessions for any failed tool calls 
   and explain what went wrong"

> "Show me patterns in my bash commands from today"

> "Analyze my token usage trends this week"
```

### SDK for Custom Tools

Build custom observability tools using the Rust SDK:

```rust
use agtrace_sdk::{Client, types::SessionFilter};

let client = Client::connect_default().await?;
let sessions = client.sessions().list(SessionFilter::all())?;

if let Some(summary) = sessions.first() {
    let handle = client.sessions().get(&summary.id)?;
    let session = handle.assemble()?;
    println!("{} turns, {} tokens",
        session.turns.len(),
        session.stats.total_tokens);
}
```

---

## 20. UV PACKAGE MANAGER

### Overview

uv is an ultra-fast Python package manager (written in Rust):

- **10-100x Faster** than pip
- **Lockfile Support** - Reproducible installs
- **Tool Management** - Install CLI tools globally
- **Virtual Environments** - Built-in venv management

### Installation

```bash
# Installed by setup.sh
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### Commands

```bash
# Install packages (in project)
uv add requests pandas

# Install tools globally
uv tool install specify-cli

# Create virtual environment
uv venv

# Sync dependencies
uv sync

# Run Python scripts
uv run python script.py

# Pip compatibility
uv pip install package-name
```

### Workflow: Python Project Setup

```bash
# 1. Create new project
mkdir my-project && cd my-project

# 2. Initialize with uv
uv init

# 3. Add dependencies
uv add fastapi uvicorn sqlalchemy

# 4. Create virtual environment
uv venv

# 5. Sync all dependencies
uv sync

# 6. Run your app
uv run uvicorn main:app --reload
```

---

## 21. DIRENV

### Overview

direnv automatically loads/unloads environment variables when entering directories.

### Installation

```bash
# Installed by setup.sh
curl -sfL https://direnv.net/install.sh | bash

# Add to shell (done by setup.sh)
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
```

### Usage

```bash
# Create .envrc in project
echo 'export DATABASE_URL="postgresql://localhost/mydb"' > .envrc

# Allow the directory
direnv allow

# Now DATABASE_URL is set when you enter this directory
cd my-project
echo $DATABASE_URL  # postgresql://localhost/mydb

# Automatically unloaded when leaving
cd ..
echo $DATABASE_URL  # (empty)
```

### Workflow: Project-Specific Environments

```bash
# 1. Create project .envrc
cat > .envrc << 'EOF'
export NODE_ENV=development
export DATABASE_URL=postgresql://localhost/mydb
export API_KEY=dev-key-12345
export PATH="$PWD/node_modules/.bin:$PATH"
EOF

# 2. Allow the configuration
direnv allow

# 3. Enter directory - variables are loaded
cd my-project
# direnv: loading .envrc
# direnv: export +API_KEY +DATABASE_URL +NODE_ENV ~PATH

# 4. Leave directory - variables are unloaded
cd ..
# direnv: unloading
```

---

## 22. COMMAND REFERENCE

### Claude Code Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `claude` | `claude` | Start Claude Code |
| `dsp` | `claude --dangerously-skip-permissions` | Skip permission prompts |

### Claude Flow Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `cf` | `npx -y claude-flow@alpha` | Claude Flow base |
| `cf-init` | `npx -y claude-flow@alpha init --force` | Initialize |
| `cf-swarm` | `npx -y claude-flow@alpha swarm` | Run swarm |
| `cf-hive` | `npx -y claude-flow@alpha hive-mind spawn` | Spawn hive-mind |
| `cf-status` | `npx -y claude-flow@alpha hive-mind status` | Check status |
| `cf-fix` | (function) | Fix better-sqlite3 |

### Agentic Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `af` | `npx -y agentic-flow` | Agentic Flow |
| `af-run` | `npx -y agentic-flow --agent` | Run agent |
| `af-coder` | `npx -y agentic-flow --agent coder` | Coder agent |
| `aqe` | `npx -y agentic-qe` | Agentic QE |
| `aj` | `npx -y agentic-jujutsu` | Agentic Jujutsu |

### Specification Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `sk` | `specify` | Spec-Kit |
| `sk-here` | `specify init . --ai claude` | Init with Claude |
| `os` | `openspec` | OpenSpec |
| `os-init` | `openspec init` | Init OpenSpec |
| `os-list` | `openspec list` | List changes |

### Skills Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `skills` | `npx ai-agent-skills` | Skills manager |
| `skills-list` | `npx ai-agent-skills list` | List skills |
| `skills-search` | `npx ai-agent-skills search` | Search skills |
| `skills-install` | `npx ai-agent-skills install` | Install skill |

### MCP Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `n8n-mcp` | `npx -y n8n-mcp` | n8n MCP server |
| `mcp-playwright` | `npx -y @playwright/mcp@latest` | Playwright MCP |
| `mcp-chrome` | `npx -y chrome-devtools-mcp@latest` | Chrome MCP |

### PAL Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `pal` | `cd ~/.pal-mcp-server && ./run-server.sh` | Start PAL |
| `pal-setup` | `cd ~/.pal-mcp-server && uv sync` | Setup PAL |

### Tmux Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `t` | `tmux` | Tmux |
| `tns` | `tmux new-session -s` | New named session |
| `ta` | `tmux attach-session` | Attach to session |
| `tl` | `tmux ls` | List sessions |
| `tks` | `tmux kill-session -t` | Kill session |

---

## 23. WORKFLOWS

### Workflow 1: New Project Setup

```bash
# 1. Create project directory
mkdir my-project && cd my-project

# 2. Initialize all tools
npm init -y
sk-here                    # Spec-Kit
os-init                    # OpenSpec  
cf-init                    # Claude Flow
aqe init                   # Agentic QE

# 3. Generate CLAUDE.md
generate-claude-md

# 4. Start development
claude
```

### Workflow 2: Feature Development (Full Pipeline)

```bash
# 1. Create specification with OpenSpec
claude
> "/openspec:proposal Add user authentication with OAuth"

# 2. Plan with SPARC
npx claude-flow sparc run spec-pseudocode "OAuth authentication"
npx claude-flow sparc run architect "OAuth authentication"

# 3. Implement with Hive-Mind
cf-hive "Implement OAuth authentication following the specs"

# 4. Test with Agentic QE
claude
> "Use qe-test-generator to create comprehensive auth tests"
> "Run tests and ensure 95% coverage"

# 5. Review with multi-model
> "Get code review from Gemini Pro on the auth implementation"

# 6. Archive the spec change
openspec archive add-oauth
```

### Workflow 3: Code Review Pipeline

```bash
# 1. Start Claude
claude

# 2. Multi-model review
> "Review the changes in my current branch using:
   - Claude for architecture review
   - Gemini for security analysis
   - O3 for performance review
   Synthesize findings into actionable items."

# 3. Apply fixes
> "Apply the suggested fixes from the review"

# 4. Final validation
> "Run qe-quality-gate to ensure all changes pass quality checks"
```

### Workflow 4: Research and Documentation

```bash
# 1. Research with Claude Flow
cf-hive "Research best practices for microservices authentication" \
  --agents researcher,analyst

# 2. Query findings
npx claude-flow@alpha memory query "authentication patterns"

# 3. Generate documentation
npx claude-flow sparc run documentation "Authentication System"

# 4. Create diagrams
claude
> "Create architecture diagrams for the authentication system"
```

### Workflow 5: Master Prompt Pattern

Use this prompt pattern to maximize agent utilization:

```
"Identify all subagents useful for this task and utilize 
claude-flow hivemind to maximize ability to accomplish:

[Your specific task here]

Steps:
1. First discover relevant agents in agents/ directory
2. Initialize Claude Flow hive-mind
3. Spawn appropriate agents for each aspect
4. Coordinate work between agents
5. Store learnings in memory
6. Produce final deliverable"
```

---

## 24. TROUBLESHOOTING

### Permission Issues

```bash
# Fix DevPod permissions
sudo chown -R $(whoami):staff ~/.devpod
find ~/.devpod -type d -exec chmod 755 {} \;
find ~/.devpod -name "*provider*" -type f -exec chmod +x {} \;
```

### Node.js Version Issues

```bash
# Check version (needs 20+)
node -v

# Upgrade with n
sudo n 20

# Or with nvm
nvm install 20
nvm use 20
```

### Claude Flow Not Initialized

```bash
# Fix with cf-fix alias
cf-fix

# Or manually
npx -y claude-flow@alpha --version
NPX_CF_DIR=$(find ~/.npm/_npx -type d -name "claude-flow" | head -1)
cd "$NPX_CF_DIR" && npm install better-sqlite3
cd - && npx -y claude-flow@alpha init --force
```

### Connection Issues

```bash
# Kill VS Code and retry
killall "Code"    # macOS
# OR
taskkill /IM Code.exe /F    # Windows

# Retry DevPod connection
devpod up turbo-flow-claude --ide vscode
```

### Verify Installation

```bash
# Check all tools
echo "Node: $(node -v)"
echo "Claude: $(which claude && echo '✓' || echo '✗')"
echo "Claude Flow: $(ls .claude-flow/ 2>/dev/null && echo '✓' || echo '✗')"
echo "Agents: $(ls -1 agents/*.md 2>/dev/null | wc -l)"
echo "Specify: $(which specify && echo '✓' || echo '✗')"
echo "OpenSpec: $(which openspec && echo '✓' || echo '✗')"

# Full verification
claude --version
specify check
skills-list
```

### MCP Server Issues

```bash
# List registered MCP servers
claude mcp list

# Remove and re-add problematic server
claude mcp remove n8n-mcp
claude mcp add n8n-mcp npx -y n8n-mcp

# Check MCP config
cat ~/.config/claude/mcp.json
```

### Memory Issues

```bash
# Check memory status
npx claude-flow@alpha memory status

# Clear all memory
npx claude-flow@alpha memory clear --namespace all

# List stored memories
npx claude-flow@alpha memory list --all
```

---

## 25. RESOURCES

### Official Documentation

| Resource | URL |
|----------|-----|
| Turbo Flow Claude | https://github.com/marcuspat/turbo-flow-claude |
| Claude Flow | https://github.com/ruvnet/claude-flow |
| Claude Flow Wiki | https://github.com/ruvnet/claude-flow/wiki |
| 610ClaudeSubagents | https://github.com/ChrisRoyse/610ClaudeSubagents |
| DevPod | https://devpod.sh/docs |
| Claude Code | https://code.claude.com/docs |
| Anthropic Docs | https://docs.anthropic.com |
| OpenSpec | https://github.com/Fission-AI/OpenSpec |
| PAL MCP | https://github.com/BeehiveInnovations/pal-mcp-server |

### Setup Guides

| Guide | File |
|-------|------|
| DevPod Provider Setup | `devpod_provider_setup_guide.md` |
| GitHub Codespaces | `github_codespaces_setup.md` |
| Google Cloud Shell | `google_cloud_shell_setup.md` |
| Rackspace Spot | `spot_rackspace_setup_guide.md` |
| macOS/Linux | `macosx_linux_setup.md` |
| Aliases Guide | `claude-flow-aliases-guide.md` |

### Community

| Resource | URL |
|----------|-----|
| Agentics Foundation Discord | https://discord.com/invite/dfxmpwkG2D |
| Claude Flow Issues | https://github.com/ruvnet/claude-flow/issues |
| Turbo Flow Issues | https://github.com/marcuspat/turbo-flow-claude/issues |

### Credits

| Contributor | Contribution |
|-------------|--------------|
| Reuven Cohen (ruvnet) | Claude Flow |
| Christopher Royse | 610ClaudeSubagents |
| Marcus Patman | Turbo Flow Claude |
| Anthropic | Claude Code CLI |
| Fission AI | OpenSpec |
| BeehiveInnovations | PAL MCP Server |
| MadAppGang | Claudish |

---

## APPENDIX: QUICK START CHEAT SHEET

```bash
# ═══════════════════════════════════════════════════════════
# TURBO FLOW CLAUDE - QUICK START CHEAT SHEET
# ═══════════════════════════════════════════════════════════

# SETUP
source ~/.bashrc              # Load aliases after install
cf-init                       # Initialize Claude Flow

# CLAUDE CODE
claude                        # Start Claude
dsp                          # Skip permissions mode

# CLAUDE FLOW
cf-swarm "task"              # Quick swarm task
cf-hive "project"            # Complex project
cf-status                    # Check status

# MEMORY
cf memory store KEY VAL      # Store
cf memory query KEY          # Retrieve

# SPARC
cf sparc tdd "task"          # TDD workflow
cf sparc modes               # List modes

# AGENTS
af "task"                    # Agentic Flow
aqe init                     # Agentic QE
aj status                    # Agentic Jujutsu

# SPECS
sk-here                      # Init Spec-Kit
os-init                      # Init OpenSpec

# SKILLS
skills-list                  # Browse skills
skills-install NAME          # Install skill

# DEVPOD
devpod up URL --ide vscode   # Create workspace
devpod stop NAME             # Stop
devpod list                  # List all
```

---

*End of Manual*

*Generated for Turbo Flow Claude v1.0.2 Alpha (Bulletproof v9)*

*For updates: https://github.com/marcuspat/turbo-flow-claude*
