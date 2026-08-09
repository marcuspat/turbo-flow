# FEEDCLAUDE.md - Essential Claude Prompting Instructions

## 🚨 CRITICAL EXECUTION RULES

**ABSOLUTE REQUIREMENTS:**
1. ALL operations MUST be concurrent/parallel in ONE message
2. NEVER save working files, text/mds and tests to the root folder
3. ALWAYS organize files in appropriate subdirectories
4. USE CLAUDE CODE'S TASK TOOL for spawning agents concurrently

### ⚡ GOLDEN RULE: "1 MESSAGE = ALL RELATED OPERATIONS"

**MANDATORY PATTERNS:**
- TodoWrite: ALWAYS batch ALL todos in ONE call (5-10+ minimum)
- Task tool: ALWAYS spawn ALL agents in ONE message
- File operations: ALWAYS batch ALL reads/writes/edits
- Bash commands: ALWAYS batch ALL terminal operations
- Memory operations: ALWAYS batch ALL store/retrieve

## 🔴 MANDATORY: Doc-Planner & Microtask-Breakdown

**EVERY task MUST start with:**

```bash
# ALWAYS load these first:
cat $WORKSPACE_FOLDER/agents/doc-planner.md
cat $WORKSPACE_FOLDER/agents/microtask-breakdown.md
```

1. **Doc-Planner Agent**: SPARC workflow, TDD methodology, atomic tasks
2. **Microtask-Breakdown Agent**: 10-minute atomic tasks, production readiness

## 🎯 Core Development Principles

1. **Playwright Integration**: All frontend/web dev requires screenshots
2. **Recursive Problem Solving**: Break to atomic units
3. **Iterate Until Success**: Never give up until goal achieved
4. **Deep Research**: Auto-search YouTube, GitHub, blogs when stuck
5. **Date Context**: Current date is Friday, August 22, 2025

## 📁 File Organization

**NEVER save to root folder. Use:**
- `/src` - Source code files
- `/tests` - Test files  
- `/docs` - Documentation and markdown files
- `/config` - Configuration files
- `/scripts` - Utility scripts
- `/examples` - Example code

## 🎯 Claude Code vs MCP Tools

### Claude Code Handles ALL EXECUTION:
- Task tool: Spawn and run agents concurrently
- File operations (Read, Write, Edit, MultiEdit, Glob, Grep)
- Code generation and programming
- Bash commands and system operations
- TodoWrite and task management
- Git operations and package management

### MCP Tools ONLY COORDINATE:
- Swarm initialization (topology setup)
- Agent type definitions (coordination patterns)
- Task orchestration (high-level planning)
- Memory management

**KEY**: MCP coordinates strategy, Claude Code executes with real agents.

## 🚀 Master Prompting Pattern

**ALWAYS include this in prompts:**
```
"Identify all of the subagents that could be useful in any way for this task and then figure out how to utilize the claude-flow hivemind to maximize your ability to accomplish the task."
```

## 🤖 Available Agents (60+ Total)

### Mandatory Agents (Use for EVERY task)
- `doc-planner` - Documentation planning, SPARC workflow
- `microtask-breakdown` - Atomic task decomposition

## 🔴 MANDATORY AGENT LOADING PROTOCOL

### ⚡ BEFORE ANY TASK: Auto-Load Mandatory Agents
```javascript
// EVERY development task MUST start with these reads:
[Single Message - Mandatory Agent Loading]:
  Read("agents/doc-planner.md")
  Read("agents/microtask-breakdown.md")
  
  // Then use Task tool with loaded agent instructions
  Task("Doc Planning", "Follow the doc-planner methodology just loaded to create comprehensive documentation plan", "planner")
  Task("Microtask Breakdown", "Follow the microtask-breakdown methodology just loaded to break into atomic 10-minute tasks", "analyst")
  
  // Continue with specialized agents
  Task("Implementation", "...", "coder")
  Task("Testing", "...", "tester")

### Core Development
- `coder` - Implementation
- `reviewer` - Code quality
- `tester` - Test creation
- `planner` - Strategic planning
- `researcher` - Information gathering

### Swarm Coordination
- `hierarchical-coordinator` - Queen-led
- `mesh-coordinator` - Peer-to-peer
- `adaptive-coordinator` - Dynamic topology
- `collective-intelligence-coordinator` - Hive-mind
- `swarm-memory-manager` - Distributed memory

### Specialized
- `backend-dev` - API development
- `mobile-dev` - React Native
- `ml-developer` - Machine learning
- `system-architect` - High-level design
- `sparc-coder` - TDD implementation
- `production-validator` - Real validation
- `performance-benchmarker` - Performance testing
- `cicd-engineer` - CI/CD pipeline
- `security-manager` - Security oversight

## 📋 Agent Coordination Protocol

## 🤖 Agent Reference (60+ Total)

## 🤖 Agent Discovery and Selection Protocol

### 🔍 MANDATORY: Agent Discovery Step
Before starting any task, ALWAYS discover available agents:

```bash
# Count total agents
ls $WORKSPACE_FOLDER/agents/*.md 2>/dev/null | wc -l

# Search for specific functionality
find $WORKSPACE_FOLDER/agents/ -name "*test*"
find $WORKSPACE_FOLDER/agents/ -name "*web*" 
find $WORKSPACE_FOLDER/agents/ -name "*api*"
find $WORKSPACE_FOLDER/agents/ -name "*game*"

# Sample random agents
ls $WORKSPACE_FOLDER/agents/*.md | shuf | head -10 | sed 's|.*/||g' | sed 's|.md||g'
```

### 🎯 Agent Selection Workflow
1. **Discover** - Run agent discovery commands
2. **Select** - Choose 3-7 relevant agents beyond mandatory 2
3. **Load** - Use `cat $WORKSPACE_FOLDER/agents/[agent-name].md`
4. **Coordinate** - Spawn via Task tool

### 🔄 Integration with Mandatory Workflow
- **BEFORE** doc-planner: Discover relevant agents for project type
- **DURING** microtask-breakdown: Select agents for each atomic task  
- **AFTER** planning: Load and coordinate selected agents

### Agents Directory Location
```bash
# DevPod automatically provides workspace variables
# No manual setup required - agents are located at:
$WORKSPACE_FOLDER/agents/

# The workspace folder is automatically set by DevPod
# Just use the paths directly without any configuration
```

### Mandatory Agents (Use for EVERY task)
| Agent | Purpose | Typical Location |
|-------|---------|----------|
| doc-planner | Documentation planning, SPARC workflow | `$WORKSPACE_FOLDER/agents/doc-planner.md` |
| microtask-breakdown | Atomic task decomposition | `$WORKSPACE_FOLDER/agents/microtask-breakdown.md` |

### Core Development
| Agent | Purpose |
|-------|---------|
| coder | Implementation |
| reviewer | Code quality |
| tester | Test creation |
| planner | Strategic planning |
| researcher | Information gathering |

### Swarm Coordination
| Agent | Purpose |
|-------|---------|
| hierarchical-coordinator | Queen-led |
| mesh-coordinator | Peer-to-peer |
| adaptive-coordinator | Dynamic topology |
| collect

**Every Agent MUST:**

**1️⃣ START:**
```bash
# Load mandatory agents first
cat $WORKSPACE_FOLDER/agents/doc-planner.md
cat $WORKSPACE_FOLDER/agents/microtask-breakdown.md

# Initialize
npx claude-flow@alpha hooks pre-task --description "[task]"
npx claude-flow@alpha hooks session-restore --session-id "swarm-[id]"
```

**2️⃣ DURING:**
```bash
npx claude-flow@alpha hooks post-edit --file "[file]" --memory-key "swarm/[agent]/[step]"
npx claude-flow@alpha hooks notify --message "[decision]"
```

**3️⃣ END:**
```bash
npx claude-flow@alpha hooks post-task --task-id "[task]"
npx claude-flow@alpha hooks session-end --export-metrics true
```

## ✅ CORRECT Execution Pattern

```javascript
// SINGLE MESSAGE with ALL operations:

// 1. Load mandatory agents
cat $WORKSPACE_FOLDER/agents/doc-planner.md
cat $WORKSPACE_FOLDER/agents/microtask-breakdown.md

// 2. Optional: MCP coordination setup
mcp__claude-flow__swarm_init { topology: "mesh", maxAgents: 8 }
mcp__claude-flow__agent_spawn { type: "doc-planner" }
mcp__claude-flow__agent_spawn { type: "microtask-breakdown" }

// 3. Claude Code Task tool spawns ALL agents
Task("Doc Planning", "Create comprehensive plan following SPARC", "doc-planner")
Task("Microtask Breakdown", "Break into 10-minute atomic tasks", "microtask-breakdown")
Task("Research agent", "Analyze requirements. Check memory for decisions.", "researcher")
Task("Coder agent", "Implement with authentication. Coordinate via hooks.", "coder")
Task("Tester agent", "Create comprehensive test suite with 90% coverage.", "tester")

// 4. Batch ALL todos in ONE call
TodoWrite { todos: [
  {id: "1", content: "Load doc-planner", status: "completed", priority: "high"},
  {id: "2", content: "Load microtask-breakdown", status: "completed", priority: "high"},
  {id: "3", content: "Research patterns", status: "in_progress", priority: "high"},
  {id: "4", content: "Design schema", status: "in_progress", priority: "high"},
  {id: "5", content: "Implement auth", status: "pending", priority: "high"},
  {id: "6", content: "Build endpoints", status: "pending", priority: "high"},
  {id: "7", content: "Write tests", status: "pending", priority: "medium"},
  {id: "8", content: "Integration tests", status: "pending", priority: "medium"}
]}

// 5. Parallel file operations
Bash "mkdir -p app/{src,tests,docs,config}"
Write "app/src/server.js"
Write "app/tests/server.test.js"
Write "app/docs/API.md"
```

## ❌ WRONG (Multiple Messages - 6x slower!)
```javascript
Message 1: mcp__claude-flow__swarm_init
Message 2: Task("agent 1")
Message 3: TodoWrite { todos: [single todo] }
Message 4: Write "file.js"
```

## 🚀 Agent Count Rules
1. **Mandatory 2**: doc-planner + microtask-breakdown ALWAYS
2. **Auto-Decide**: Simple (3-4), Medium (5-7), Complex (8-12)

## 📊 Progress Format
```
📊 Progress Overview
├── Planning: ✅ doc-planner | ✅ microtask-breakdown
├── Total: X | ✅ Complete: X | 🔄 Active: X | ⭕ Todo: X
└── Priority: 🔴 HIGH | 🟡 MEDIUM | 🟢 LOW
```

## 🎯 SPARC Commands
- `npx claude-flow sparc run <mode> "<task>"` - Execute mode
- `npx claude-flow sparc tdd "<feature>"` - TDD workflow
- `npx claude-flow sparc batch <modes> "<task>"` - Parallel execution

## 🔧 Mandatory Agent Protocol
**EVERY task begins with:**
1. Load and execute doc-planner
2. Load and execute microtask-breakdown  
3. Only then proceed with implementation

## 🎯 Work Chunking Protocol (WCP)

### PHASE 1: Planning (MANDATORY)
```bash
# ALWAYS start with:
cat $WORKSPACE_FOLDER/agents/doc-planner.md
cat $WORKSPACE_FOLDER/agents/microtask-breakdown.md
```

### KEY RULES:
- ALWAYS start with doc-planner and microtask-breakdown
- ONE feature at a time to production
- 100% CI before progression
- Playwright for visual verification
- Swarm for complex features
- Implementation-first focus

## 🔄 CI Protocol: Fix→Test→Commit→Push→Monitor→Repeat

### Research Phase:
1. Deploy researcher/analyst via swarm
2. Deep research: YouTube, GitHub, blogs
3. Current date context: Friday, August 22, 2025
4. Focus on specific CI failures

### Implementation Phase:
5. Implementation-first: Fix logic not test expectations
6. Iterate until success - never give up
7. Recursive problem breakdown
8. Swarm execution with hooks/memory coordination

### Monitoring Phase:
```bash
# Active monitoring ALWAYS required
gh run list --repo owner/repo --limit N
gh run view RUN_ID --repo owner/repo
npx claude-flow@alpha hooks ci-monitor-init --adaptive true
```

## 🧪 Playwright Integration (MANDATORY for web dev)
```bash
# Install playwright for visual verification
npm install -D playwright

# Visual verification test
test('dashboard renders correctly', async ({ page }) => {
  await page.goto('https://staging.app.com');
  await page.screenshot({ path: 'dashboard.png', fullPage: true });
  await expect(page.locator('.dashboard')).toBeVisible();
});

# Run with screenshots
npx playwright test --screenshot=on
```

## 🎯 Performance Tips
1. **Doc-First** - ALWAYS start with doc-planner
2. **Atomic Tasks** - Use microtask-breakdown for 10-min tasks
3. **Batch Everything** - Multiple operations = 1 message  
4. **Parallel First** - Think concurrent execution
5. **Memory is Key** - Cross-agent coordination
6. **Monitor Progress** - Real-time tracking
7. **Enable Hooks** - Automated coordination

## 🔗 Essential Locations
```bash
# Agents directory (DevPod auto-provides $WORKSPACE_FOLDER)
$WORKSPACE_FOLDER/agents/

# MANDATORY agents to load first:
$WORKSPACE_FOLDER/agents/doc-planner.md
$WORKSPACE_FOLDER/agents/microtask-breakdown.md
```

## 🚀 Quick Setup
```bash
# Add Claude Flow MCP server
claude mcp add claude-flow npx claude-flow@alpha mcp start
```

## 🎯 Development Workflow Summary
1. **ALWAYS START** with doc-planner and microtask-breakdown
2. **Use Playwright** for all visual verification  
3. **Iterate until success** - never give up
4. **Deep research** when stuck (YouTube, GitHub, blogs)
5. **Batch operations** in single messages
6. **Current date**: Friday, August 22, 2025
7. **Monitor** with ML-enhanced predictions

---

## 🔴 CRITICAL REMINDERS FOR CLAUDE:

- **NEVER create files unless absolutely necessary**
- **ALWAYS prefer editing existing files to creating new ones**
- **NEVER proactively create documentation files unless explicitly requested**
- **Never save working files, text/mds and tests to the root folder**
- **Do what has been asked; nothing more, nothing less**

**SUCCESS = Doc-First + Atomic Tasks + Visual Verification + Persistent Iteration**

**Remember: Claude Flow coordinates, Claude Code creates!**
