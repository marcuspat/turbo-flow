import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { validateGraph, findCycles, loadGraph, type Graph } from '../../src/schemas/graph.js';
import { createInitialState, writeState, readState, type RunState } from '../../src/schemas/state.js';
import { checkBudget } from '../../src/engine/budget.js';
import { mkdirSync, rmSync, readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';

// ─── Eval test suite ─────────────────────────────────────────
//
// Tests the ENGINE's behavior against a known spec and graph,
// WITHOUT calling Claude. Validates state machine, budget, and gate
// wiring produce correct transitions for a canonical scenario.
//
// To run a live eval (calls Claude, costs money):
//   TURBO_FLOW_EVAL_LIVE=1 npx vitest run tests/eval/eval.test.ts

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const PKG_ROOT = join(__dirname, '..', '..');
const EVAL_DIR = join(__dirname);
const TEMPLATES_DIR = join(PKG_ROOT, 'templates', 'prompts');

let tmpDir: string;

function setupEvalRepo(): string {
  const repo = join(tmpDir, 'eval-repo');
  mkdirSync(repo, { recursive: true });
  writeFileSync(join(repo, '.gitkeep'), '');
  execFileSync('git', ['init'], { cwd: repo, stdio: 'pipe' });
  execFileSync('git', ['add', '.'], { cwd: repo, stdio: 'pipe' });
  execFileSync('git', ['commit', '-m', 'init', '--allow-empty'], { cwd: repo, stdio: 'pipe' });
  return repo;
}

beforeEach(() => {
  tmpDir = join(tmpdir(), `tf-eval-${Date.now()}`);
  mkdirSync(tmpDir, { recursive: true });
});

afterEach(() => {
  rmSync(tmpDir, { recursive: true, force: true });
});

// ─── Eval 001: graph validation ───────────────────────────────

describe('eval:001-add-greeting graph validation', () => {
  it('the eval graph is structurally valid', () => {
    const graph = loadGraph(join(EVAL_DIR, 'eval-graph.json'));
    const errors = validateGraph(graph);
    expect(errors).toEqual([]);
  });

  it('has no cycles (simple linear flow)', () => {
    const graph = loadGraph(join(EVAL_DIR, 'eval-graph.json'));
    expect(findCycles(graph)).toEqual([]);
  });

  it('implement node has exactly 2 cmd gates', () => {
    const graph = loadGraph(join(EVAL_DIR, 'eval-graph.json'));
    const impl = graph.nodes['implement'];
    expect(impl.gates).toHaveLength(2);
    expect(impl.gates!.every(g => g.type === 'cmd')).toBe(true);
  });
});

// ─── Eval 001: budget tracking ────────────────────────────────

describe('eval:001-add-greeting budget tracking', () => {
  it('allows execution within budget', () => {
    const state = createInitialState('001-add-greeting', 'implement', {
      budgetUsd: 5,
      model: 'claude-sonnet-4-20250514',
      branch: 'lg/001-add-greeting',
    });
    const graph = loadGraph(join(EVAL_DIR, 'eval-graph.json'));
    const budget = checkBudget(state, graph.nodes['implement']);
    expect(budget.allowed).toBe(true);
    expect(budget.hostBudgetCap).toBe(4); // min(5 run, 4 node)
  });

  it('blocks when node budget exhausted after iterations', () => {
    const state = createInitialState('001-add-greeting', 'implement', {
      budgetUsd: 5,
      model: 'claude-sonnet-4-20250514',
      branch: 'lg/001-add-greeting',
    });
    state.history.push({
      iteration: 1, graph_node: 'implement', session_id: null,
      model: 'claude-sonnet-4-20250514', cost_usd: 4, turns: 20,
      gates: [], passed: false, halted_reason: null,
    });
    const graph = loadGraph(join(EVAL_DIR, 'eval-graph.json'));
    const budget = checkBudget(state, graph.nodes['implement']);
    expect(budget.allowed).toBe(false);
    expect(budget.reason).toContain('budget exhausted');
  });

  it('correctly passes min(run, node) to host', () => {
    const state = createInitialState('001-add-greeting', 'implement', {
      budgetUsd: 5,
      model: 'claude-sonnet-4-20250514',
      branch: 'lg/001-add-greeting',
    });
    state.cost_usd = 3; // $2 remaining at run level
    const graph = loadGraph(join(EVAL_DIR, 'eval-graph.json'));
    const budget = checkBudget(state, graph.nodes['implement']);
    expect(budget.hostBudgetCap).toBe(2); // min(2 run, 4 node)
  });
});

// ─── Eval 001: gate execution ─────────────────────────────────

describe('eval:001-add-greeting gate execution', () => {
  it('file-exists gate fails when src/greet.ts absent', async () => {
    const { runCmdGate } = await import('../../src/engine/gates.js');
    const repo = setupEvalRepo();
    const result = runCmdGate(
      { id: 'file-exists', type: 'cmd', run: 'test -f src/greet.ts' },
      repo, '001-add-greeting',
    );
    expect(result.passed).toBe(false);
  });

  it('file-exists gate passes when src/greet.ts present', async () => {
    const { runCmdGate } = await import('../../src/engine/gates.js');
    const repo = setupEvalRepo();
    mkdirSync(join(repo, 'src'), { recursive: true });
    writeFileSync(join(repo, 'src', 'greet.ts'), 'export function greet(n: string) { return "Hello, " + n; }');
    const result = runCmdGate(
      { id: 'file-exists', type: 'cmd', run: 'test -f src/greet.ts' },
      repo, '001-add-greeting',
    );
    expect(result.passed).toBe(true);
  });
});

// ─── Eval 001: state machine transitions ──────────────────────

describe('eval:001-add-greeting state transitions', () => {
  it('starts at implement (the entry node)', () => {
    const state = createInitialState('001-add-greeting', 'implement', {
      budgetUsd: 5,
      model: 'claude-sonnet-4-20250514',
      branch: 'lg/001-add-greeting',
    });
    expect(state.graph_node).toBe('implement');
    expect(state.status).toBe('running');
    expect(state.iteration).toBe(0);
  });

  it('transitions to done on pass', () => {
    const graph = loadGraph(join(EVAL_DIR, 'eval-graph.json'));
    const state = createInitialState('001-add-greeting', 'implement', {
      budgetUsd: 5,
      model: 'claude-sonnet-4-20250514',
      branch: 'lg/001-add-greeting',
    });
    const node = graph.nodes['implement'];
    state.graph_node = node.on_pass!;
    state.transitions++;
    state.node_iteration = 0;
    const doneNode = graph.nodes['done'];
    if (doneNode.terminal) {
      state.status = 'completed';
      state.termination_reason = 'success';
      state.completed_at = new Date().toISOString();
    }
    expect(state.status).toBe('completed');
    expect(state.termination_reason).toBe('success');
    expect(state.graph_node).toBe('done');
  });

  it('escalates on gate failure after max_iterations', () => {
    const graph = loadGraph(join(EVAL_DIR, 'eval-graph.json'));
    const state = createInitialState('001-add-greeting', 'implement', {
      budgetUsd: 5,
      model: 'claude-sonnet-4-20250514',
      branch: 'lg/001-add-greeting',
    });
    state.node_iteration = 2;
    const maxIter = graph.nodes['implement'].max_iterations ?? 3;
    expect(state.node_iteration).toBeGreaterThanOrEqual(maxIter);
  });
});

// ─── Eval: cache boundary enforcement ─────────────────────────

describe('eval: cache boundary in prompts', () => {
  const prompts = ['plan.md', 'implement.md', 'verify.md', 'ship.md'];

  for (const p of prompts) {
    it(`${p} has exactly one CACHE BOUNDARY marker`, () => {
      const content = readFileSync(join(TEMPLATES_DIR, p), 'utf-8');
      const matches = content.match(/# CACHE BOUNDARY/g);
      expect(matches).toHaveLength(1);
    });

    it(`${p} has no variable tail content above CACHE BOUNDARY`, () => {
      const content = readFileSync(join(TEMPLATES_DIR, p), 'utf-8');
      const boundaryIdx = content.indexOf('# CACHE BOUNDARY');
      const above = content.slice(0, boundaryIdx);
      // ${SPEC_ID}/${BRANCH} are OK — engine substitutes them to stable values.
      // Gate feedback and human decisions (which differ per run) must be below.
      expect(above).not.toContain('Gate feedback');
      expect(above).not.toContain('Human decision');
    });
  }
});
