# Addendum: Git Operations, Slash Commands & GitHub Integration

> **Append this to the Definitive Guide, Quick Reference, and Prompt Guide.**
> Covers: Claude Code built-in slash commands, Ruflo GitHub agents, git workflow skills, and custom command patterns.

---

## Claude Code Built-In Slash Commands

These are hardcoded into the Claude Code CLI. They are NOT Ruflo or TurboFlow — they work in any Claude Code session.

| Command | Purpose |
|---------|---------|
| `/help` | List all available commands |
| `/compact [focus]` | Compress conversation context. Add focus: `/compact retain the auth flow and test results` |
| `/clear` | Clear conversation history (use when switching tasks) |
| `/model [name]` | Switch model mid-session: `/model opus`, `/model sonnet`, `/model haiku` |
| `/cost` | Show token usage and cost statistics |
| `/context` | Visualize current context window usage (colored grid) |
| `/plan` | Enter plan mode — Claude designs approach without making changes |
| `/review` | Code review of recent git changes (bundled skill) |
| `/init` | Initialize project with CLAUDE.md |
| `/diff` | Interactive diff viewer of all changes Claude has made |
| `/config` | Open settings interface |
| `/doctor` | Check installation health |
| `/export [file]` | Export conversation to file or clipboard |
| `/hooks` | Manage hook configurations |
| `/ide` | Manage IDE integrations |
| `/agents` | Manage custom AI subagents |
| `/bashes` | List and manage background tasks |
| `/add-dir` | Add additional working directories |
| `/login` | Switch accounts |
| `/logout` | Log out |
| `/memory` | Review/edit what Claude has remembered about your project |
| `/resume` | Resume a previous session |
| `/exit` | Exit the REPL |
| `/bug` | Report bugs to Anthropic |
| `/install-github-app` | Set up Claude GitHub Actions |

### Built-In Skills (bundled with Claude Code)

These are prompt-based — Claude orchestrates them using its tools:

| Skill | What it does |
|-------|-------------|
| `/review` | Structured code review of recent git changes |
| `/simplify` | Simplify complex code |
| `/debug` | Debug with structured approach |
| `/batch` | Batch operations across files |
| `/loop` | Evaluator-optimizer loop |
| `/claude-api` | Build with the Anthropic API |
| `/plan` | Plan mode — design before implementing |
| `/btw` | Side question without polluting main context |

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Shift+Tab` | Cycle: normal → auto-accept → plan mode |
| `Cmd+T` / `Ctrl+T` | Toggle Extended Thinking |
| `Cmd+P` / `Ctrl+P` | Model picker |
| `Ctrl+G` | Open external editor |
| `Ctrl+R` | Search command history |
| `Esc Esc` | Rewind (/rewind) |
| `!command` | Execute shell command and embed output in context |

---

## Git Workflow Prompts

### Prompt: Smart Commit

```
Review the current git diff. Generate a Conventional Commit message following this format:
type(scope): description

Types: feat, fix, docs, style, refactor, perf, test, chore, ci
Scope: the bounded context or module affected

Stage all changes, commit with the generated message, and show me the commit before pushing.
```

### Prompt: Create Branch from Task

```
Create a feature branch for [task description]:
1. Ensure we're on main and it's up to date: git checkout main && git pull
2. Create branch: git checkout -b feat/[short-description]
3. If using Beads, claim the task: bd update <task-id> --claim

Branch naming conventions:
- feat/[name] — new features
- fix/[name] — bug fixes
- hotfix/[name] — production hotfixes
- refactor/[name] — refactoring
- docs/[name] — documentation only
- chore/[name] — maintenance tasks
```

### Prompt: Create PR

```
Create a pull request for the current branch:
1. Run all tests to verify nothing is broken
2. Run /review to self-review changes
3. Generate a PR title from the branch name and commit history
4. Generate a PR description covering:
   - What changed and why
   - How to test
   - Screenshots (if UI changes)
   - Related issues/tasks (reference Beads IDs if applicable)
5. Open the PR: gh pr create --title "[title]" --body "[body]"
6. If Beads is active: bd comments add <task-id> "PR opened: [url]"
```

### Prompt: Review PR

```
Review PR #[number]:
1. Fetch the PR diff: gh pr diff [number]
2. Analyze for:
   - Correctness: logic bugs, edge cases, error handling
   - Security: injection, auth bypass, data exposure
   - Performance: N+1 queries, memory leaks, unnecessary computation
   - Tests: adequate coverage, meaningful assertions
   - Style: naming conventions, code organization
3. Cross-reference with GitNexus blast radius: gnx-analyze
4. Provide specific, actionable feedback by priority (critical/warning/info)
```

### Prompt: Merge and Clean Up

```
Merge the current branch to main:
1. Ensure all CI checks pass
2. Rebase on latest main: git fetch origin && git rebase origin/main
3. Resolve any conflicts
4. Run tests one final time
5. Merge: git checkout main && git merge --no-ff [branch]
6. Push: git push origin main
7. Delete the branch: git branch -d [branch] && git push origin --delete [branch]
8. Update Beads: bd close <task-id> --reason "Merged to main"
9. Update knowledge graph: gnx-analyze (native: npx gitnexus analyze)
```

### Prompt: Git Stash and Switch Context

```
I need to switch to a different task without losing my current work:
1. Stash current changes: git stash push -m "[description of work in progress]"
2. Switch to the other branch or create new worktree: wt-add [new-task]
3. Do the other work
4. When done, switch back and restore: git stash pop
5. Verify stash applied correctly: git diff
```

### Prompt: Revert a Bad Deploy

```
Emergency: revert the last deployment:
1. Identify the bad commit: git log --oneline -5
2. Create a revert commit: git revert [commit-hash] --no-edit
3. Run smoke tests on the revert
4. Push immediately: git push origin main
5. Record in Beads: bd create "REVERT: [commit-hash] — [reason]" -t bug -p 0
6. Create follow-up fix task: bd create "Fix: [root cause from reverted change]" -t task -p 1
```

### Prompt: Interactive Rebase / Squash

```
Clean up the commit history on the current branch before PR:
1. Count commits on this branch: git log --oneline main..[branch]
2. Interactive rebase: git rebase -i main
3. Squash related commits into logical units
4. Reword commit messages to follow Conventional Commits
5. Force push: git push --force-with-lease
```

### Prompt: Cherry-Pick Fix to Production

```
Cherry-pick a specific fix from main to the production branch:
1. Identify the commit: git log --oneline main | grep "[fix description]"
2. Switch to production: git checkout production
3. Cherry-pick: git cherry-pick [commit-hash]
4. Resolve any conflicts
5. Test: run the specific test suite for the affected module
6. Push: git push origin production
7. Record: bd create "Cherry-picked [hash] to production" -t task -p 1
```

---

## Ruflo GitHub Integration Agents

Ruflo provides 13 specialized GitHub agents. These are spawned via CLI or MCP.

### Prompt: Automated PR Management

```bash
# Spawn PR manager to review and merge ready PRs
npx ruflo@latest agent spawn --agentType pr-manager --task "Review and merge ready PRs"

# Spawn multi-reviewer swarm for comprehensive code analysis
npx ruflo@latest agent spawn --agentType code-review-swarm --task "Perform security, performance, and style review"
```

### Prompt: Release Management

```bash
# Spawn release manager for full release lifecycle
npx ruflo@latest agent spawn --agentType release-manager --task "Prepare v[X.Y.Z] release"
```

### Prompt: Issue Triage

```bash
# Spawn issue tracker for automated triage
npx ruflo@latest agent spawn --agentType issue-tracker --task "Triage and label new issues"
```

### Prompt: Multi-Repo Operations

```bash
# Synchronize changes across microservices
npx ruflo@latest agent spawn --agentType multi-repo-swarm --task "Synchronize API changes across microservices"
```

### Prompt: GitHub Metrics

```bash
# Generate repository health report
npx ruflo@latest agent spawn --agentType github-modes --task "Generate monthly activity report"
```

### Prompt: Workflow Automation

```bash
# Create GitHub Actions workflows
npx ruflo@latest agent spawn --agentType workflow-automation --task "Create deployment workflow for staging environment"
```

---

## Custom Slash Commands (Create Your Own)

Custom commands live in `.claude/commands/` (project-level) or `~/.claude/commands/` (personal).

### Example: /commit

```markdown
<!-- .claude/commands/commit.md -->
---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git diff:*)
description: Smart commit with conventional message
model: claude-3-5-haiku-20241022
---
1. Run `git diff --staged` to see what's staged (or `git diff` if nothing staged)
2. If nothing is staged, stage all changes: `git add -A`
3. Generate a Conventional Commit message from the diff
4. Commit with the generated message
5. Show the commit log entry
```

### Example: /pr

```markdown
<!-- .claude/commands/pr.md -->
---
allowed-tools: Bash(gh:*), Bash(git:*), Read, Grep
description: Create a PR with auto-generated description
---
1. Get current branch: `git branch --show-current`
2. Get commits on this branch: `git log --oneline main..HEAD`
3. Generate PR title and description from commits
4. Check if PR already exists: `gh pr list --head $(git branch --show-current)`
5. If not, create: `gh pr create --title "[title]" --body "[body]"`
6. Output the PR URL
```

### Example: /push

```markdown
<!-- .claude/commands/push.md -->
---
allowed-tools: Bash(git:*)
description: Stage, commit, and push in one command
argument-hint: [commit message]
---
1. Stage all changes: `git add -A`
2. If $ARGUMENTS provided, use as commit message
3. If not, generate Conventional Commit message from diff
4. Commit and push: `git commit -m "[message]" && git push`
```

### Example: /branch

```markdown
<!-- .claude/commands/branch.md -->
---
allowed-tools: Bash(git:*)
description: Create a feature branch from main
argument-hint: [description]
---
1. Checkout main and pull: `git checkout main && git pull origin main`
2. Convert $ARGUMENTS to kebab-case slug
3. Create branch: `git checkout -b feat/[slug]`
4. Confirm the branch was created
```

### Example: /review-pr

```markdown
<!-- .claude/commands/review-pr.md -->
---
allowed-tools: Bash(gh:*), Bash(git:*), Read, Grep, Glob
description: Comprehensive PR review
argument-hint: [PR number]
context: fork
---
## Changed Files
!`gh pr diff $1 --name-only`

## Detailed Changes
!`gh pr diff $1`

## Review Checklist
1. Code quality and readability
2. Security vulnerabilities
3. Performance implications
4. Test coverage
5. Documentation completeness

Provide specific, actionable feedback by priority.
```

### Example: /fix-issue

```markdown
<!-- .claude/commands/fix-issue.md -->
---
allowed-tools: Bash, Read, Edit, Grep, Glob
argument-hint: [issue-number]
description: Analyze and fix a GitHub issue
---
1. Fetch issue details: `gh issue view $1`
2. Analyze the issue description and any linked code
3. Create a fix branch: `git checkout -b fix/issue-$1`
4. Implement the fix
5. Write tests for the fix
6. Commit with message: `fix: resolve #$1 — [description]`
```

### Example: /merge-to-main

```markdown
<!-- .claude/commands/merge-to-main.md -->
---
allowed-tools: Bash(git:*), Bash(gh:*), Bash(npm test:*)
description: Merge current branch to main safely
---
1. Run tests: `npm test`
2. If tests fail, stop and report
3. Fetch latest: `git fetch origin main`
4. Rebase: `git rebase origin/main`
5. If conflicts, stop and report
6. Checkout main: `git checkout main`
7. Merge: `git merge --no-ff [current-branch]`
8. Push: `git push origin main`
9. Delete branch: `git branch -d [branch] && git push origin --delete [branch]`
```

---

## Ruflo Skills (Auto-Activated)

In Ruflo v3.5/TurboFlow v4, slash commands have been replaced by auto-activated skills. Just describe what you want naturally:

| What you say | Skill that activates |
|-------------|---------------------|
| "Let's pair program on this" | `pair-programming` |
| "Review this PR for security" | `github-code-review` |
| "Create a swarm to build this API" | `swarm-orchestration` |
| "Build this feature with TDD" | `sparc-methodology` |
| "Use vector search to find similar code" | `agentdb-vector-search` |
| "Find bottlenecks in this code" | `performance-analysis` |
| "Deploy this to production" | `devops` |
| "Scan this for vulnerabilities" | `security` |

You can still invoke skills explicitly via Claude Code slash commands:
```bash
# In Claude Code (these are Claude Code skills, not Ruflo CLI commands)
/github-code-review
/pair-programming --mode tdd
/v3-security-overhaul
```

---

## Claims System (Multi-Agent Coordination)

Ruflo's Claims system manages who is working on what — human or agent. It prevents conflicts and enables handoffs. Claims are accessed via MCP tools (when the ruflo MCP server is registered in Claude Code).

```
# Claim a task (via MCP tool)
mcp__ruflo__claims_claim { issueId: "<issue-number>", claimant: "human:user-1:alice" }

# Agent claims work (via MCP tool)
mcp__ruflo__claims_claim { issueId: "<issue-number>", claimant: "agent:coder-1:coder" }

# List all active claims (via MCP tool)
mcp__ruflo__claims_list { status: "active" }

# Release a claim / handoff (via MCP tool)
mcp__ruflo__claims_release { issueId: "<issue-number>", claimant: "agent:coder-1:coder" }

# Transfer between agents (via MCP tool)
mcp__ruflo__claims_handoff { issueId: "<issue-number>", from: "agent:coder-1:coder", to: "agent:coder-2:coder" }
```

---

## GitHub Actions Integration

### Prompt: Set Up AI Code Review in CI

```
Create a GitHub Actions workflow for AI-powered code review:

.github/workflows/ai-review.yml:
- Trigger on pull_request (opened, synchronize)
- Checkout code with full history
- Install Ruflo: npx ruflo@latest init
- Get changed files
- Spawn code review swarm for the PR
- Post review comments via gh pr comment
```

### Prompt: Set Up AI Documentation Generation in CI

```
Create a GitHub Actions workflow for auto-generating documentation:

.github/workflows/docs.yml:
- Trigger on push to main (src/** or lib/** paths)
- Install Ruflo + documentation tools
- Run documentation swarm with 6 agents
- Commit generated docs to docs/ branch
- Create PR with the documentation updates
```

---

## Session Management & Context Optimization

### Prompt: Optimize Long Session

```
My context window is getting full. Optimize the session:
1. Run /cost to check current spend
2. Run /context to see what's using space
3. Run /compact retain [key information to preserve]
4. If switching tasks entirely, use /clear instead
5. For expensive operations, spawn a subagent (runs in its own context)
6. Switch to /model sonnet for routine work, /model opus only for complex reasoning
```

### Prompt: Model Switching Strategy

```
Use this model switching strategy for cost optimization:
1. Start with Sonnet for most tasks (80% of work at lower cost)
2. Switch to Opus for: architecture decisions, complex debugging, security analysis
3. Switch to Haiku for: test generation, linting, boilerplate, formatting
4. Switch back to Sonnet when the hard part is done

Commands:
/model sonnet    # Default working model
/model opus      # Complex reasoning
/model haiku     # Fast, cheap tasks
```

---

*Addendum for Turbo Flow v4.0 + Ruflo v3.5 guides · March 2026*
