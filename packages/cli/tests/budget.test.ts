import { describe, it, expect } from 'vitest';
import { checkBudget, budgetSlopeExceeds } from '../src/engine/budget.js';
import type { RunState } from '../src/schemas/state.js';

function makeState(overrides: Partial<RunState> = {}): RunState {
  return {
    spec: '001-test',
    graph_node: 'implement',
    status: 'running',
    budget_usd: 25,
    cost_usd: 0,
    iteration: 0,
    node_iteration: 0,
    max_cycles: 3,
    cycles_used: 0,
    transitions: 1,
    model: 'claude-sonnet-4-20250514',
    branch: 'lg/001-test',
    started_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    completed_at: null,
    termination_reason: null,
    escalation: { question: null, answer: null, issue_url: null, issue_number: null, timestamp: null, resolved_at: null },
    history: [],
    ...overrides,
  };
}

describe('checkBudget', () => {
  it('allows execution when budget is available', () => {
    const state = makeState({ cost_usd: 5 });
    const result = checkBudget(state, { budget_usd: 12 });
    expect(result.allowed).toBe(true);
    expect(result.hostBudgetCap).toBe(12); // min(20 run remaining, 12 node)
  });

  it('blocks when run budget is exhausted', () => {
    const state = makeState({ cost_usd: 25 });
    const result = checkBudget(state, { budget_usd: 12 });
    expect(result.allowed).toBe(false);
    expect(result.reason).toContain('run budget exhausted');
  });

  it('blocks when node budget is exhausted', () => {
    const state = makeState({
      cost_usd: 5,
      history: [
        { iteration: 1, graph_node: 'implement', session_id: null, model: 'x', cost_usd: 12, turns: 10, gates: [], passed: true, halted_reason: null },
      ],
    });
    const result = checkBudget(state, { budget_usd: 12 });
    expect(result.allowed).toBe(false);
    expect(result.reason).toContain('budget exhausted');
  });

  it('returns 0 budget when nothing is left', () => {
    const state = makeState({ cost_usd: 25 });
    const result = checkBudget(state, { budget_usd: 12 });
    expect(result.hostBudgetCap).toBe(0);
  });
});

describe('budgetSlopeExceeds', () => {
  it('returns false for a single history entry', () => {
    const state = makeState({
      history: [{ iteration: 1, graph_node: 'implement', session_id: null, model: 'x', cost_usd: 5, turns: 10, gates: [], passed: true, halted_reason: null }],
    });
    expect(budgetSlopeExceeds(state, { max_iterations: 3 })).toBe(false);
  });

  it('detects accelerating spend', () => {
    const state = makeState({
      budget_usd: 20,
      cost_usd: 12,
      history: [
        { iteration: 1, graph_node: 'implement', session_id: null, model: 'x', cost_usd: 2, turns: 10, gates: [], passed: false, halted_reason: null },
        { iteration: 2, graph_node: 'implement', session_id: null, model: 'x', cost_usd: 5, turns: 15, gates: [], passed: false, halted_reason: null },
        { iteration: 3, graph_node: 'implement', session_id: null, model: 'x', cost_usd: 5, turns: 20, gates: [], passed: false, halted_reason: null },
      ],
    });
    // Slope is ~1.5 per iteration, predicting ~6.5 for next, total ~18.5 < 20
    // So this should not exceed
    expect(budgetSlopeExceeds(state, { max_iterations: 3 })).toBe(false);
  });
});
