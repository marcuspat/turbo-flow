import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { validateGraph, findCycles, loadGraph, type Graph } from '../src/schemas/graph.js';
import { validateVerdict } from '../src/schemas/verdict.js';
import { createInitialState, readState, writeState, statePath } from '../src/schemas/state.js';
import { mkdirSync, rmSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

// ─── Graph schema ─────────────────────────────────────────────

describe('validateGraph', () => {
  const validGraph: Graph = {
    version: 1,
    name: 'test',
    entry: 'a',
    nodes: {
      a: { on_pass: 'b', on_fail: 'escalate' },
      b: { on_pass: 'done', on_fail: 'a' },
      done: { terminal: true },
      escalate: { terminal: true, escalates: true },
    },
  };

  it('passes for a valid graph', () => {
    expect(validateGraph(validGraph)).toEqual([]);
  });

  it('catches missing entry node', () => {
    const g = { ...validGraph, entry: 'nonexistent' };
    const errors = validateGraph(g);
    expect(errors).toHaveLength(1);
    expect(errors[0]).toContain('nonexistent');
  });

  it('catches invalid edge targets', () => {
    const g: Graph = { ...validGraph, nodes: { ...validGraph.nodes, a: { on_pass: 'nowhere' } } };
    const errors = validateGraph(g);
    expect(errors.some(e => e.includes('nowhere'))).toBe(true);
  });
});

describe('findCycles', () => {
  it('detects the verify→implement cycle', () => {
    const g: Graph = {
      version: 1, name: 'test', entry: 'a',
      nodes: {
        a: { on_pass: 'b' },
        b: { on_pass: 'c', on_fail: 'a' },
        c: { terminal: true },
      },
    };
    const cycles = findCycles(g);
    expect(cycles).toEqual([['b', 'a']]);
  });

  it('returns empty for acyclic graphs', () => {
    const g: Graph = {
      version: 1, name: 'test', entry: 'a',
      nodes: {
        a: { on_pass: 'b' },
        b: { on_pass: 'c' },
        c: { terminal: true },
      },
    };
    expect(findCycles(g)).toEqual([]);
  });
});

describe('loadGraph', () => {
  const tmpDir = join(tmpdir(), 'tf-graph-test');

  it('loads and parses a valid graph.json', () => {
    mkdirSync(tmpDir, { recursive: true });
    writeFileSync(join(tmpDir, 'graph.json'), JSON.stringify({ version: 1, name: 't', entry: 'x', nodes: { x: { terminal: true } } }));
    const g = loadGraph(join(tmpDir, 'graph.json'));
    expect(g.entry).toBe('x');
    rmSync(tmpDir, { recursive: true, force: true });
  });
});

// ─── Verdict schema ───────────────────────────────────────────

describe('validateVerdict', () => {
  it('passes for a valid verdict', () => {
    const v = { pass: true, blocking: [], needs_human: false, evidence: ['checked file X'] };
    expect(validateVerdict(v).valid).toBe(true);
  });

  it('fails if pass is not boolean', () => {
    const v = { pass: 'yes', blocking: [], needs_human: false, evidence: [] };
    expect(validateVerdict(v).valid).toBe(false);
  });

  it('fails if evidence is missing', () => {
    const v = { pass: true, blocking: [], needs_human: false };
    expect(validateVerdict(v).valid).toBe(false);
  });

  it('fails if needs_human is true but no question', () => {
    const v = { pass: false, blocking: ['missing auth'], needs_human: true, evidence: [] };
    expect(validateVerdict(v).valid).toBe(false);
  });

  it('passes when needs_human has a question', () => {
    const v = { pass: false, blocking: ['scope call'], needs_human: true, question: 'Use library X or Y?', evidence: ['read spec'] };
    expect(validateVerdict(v).valid).toBe(true);
  });
});

// ─── State management ──────────────────────────────────────────

describe('state management', () => {
  const tmpDir = join(tmpdir(), 'tf-state-test');

  beforeEach(() => {
    mkdirSync(tmpDir, { recursive: true });
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('creates initial state with correct defaults', () => {
    const s = createInitialState('001-test', 'plan', {
      budgetUsd: 25,
      model: 'claude-sonnet-4-20250514',
      branch: 'lg/001-test',
    });
    expect(s.spec).toBe('001-test');
    expect(s.graph_node).toBe('plan');
    expect(s.status).toBe('running');
    expect(s.budget_usd).toBe(25);
    expect(s.cost_usd).toBe(0);
    expect(s.max_cycles).toBe(3);
    expect(s.history).toEqual([]);
    expect(s.escalation.question).toBeNull();
  });

  it('writes and reads state', () => {
    const s = createInitialState('001-test', 'plan', {
      budgetUsd: 30,
      model: 'claude-opus-4-20250514',
      branch: 'lg/001-test',
    });
    writeState(s, tmpDir);

    const loaded = readState('001-test', tmpDir);
    expect(loaded).not.toBeNull();
    expect(loaded!.spec).toBe('001-test');
    expect(loaded!.budget_usd).toBe(30);
  });

  it('returns null for non-existent state', () => {
    expect(readState('999-nope', tmpDir)).toBeNull();
  });
});
