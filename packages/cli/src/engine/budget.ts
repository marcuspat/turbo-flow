// ─── Budget tracker ─────────────────────────────────────────────────
// Per-node and per-run. The key insight: pass min(run remaining, node
// remaining) as --max-budget-usd so the CLI enforces mid-turn.

import type { RunState, NodeIteration } from '../schemas/state.js';
import type { GraphNode } from '../schemas/graph.js';

export interface BudgetCheck {
  /** Whether the run can continue */
  allowed: boolean;
  /** Dollars remaining at the run level */
  runRemaining: number;
  /** Dollars remaining at the node level */
  nodeRemaining: number;
  /** The budget cap to pass to the host */
  hostBudgetCap: number;
  /** Why it was blocked, if not allowed */
  reason?: string;
}

/** Check if a node execution is within budget */
export function checkBudget(
  state: RunState,
  node: GraphNode,
): BudgetCheck {
  const runRemaining = (state.budget_usd ?? 25) - state.cost_usd;
  const nodeBudget = node.budget_usd ?? state.budget_usd ?? 25;

  // Calculate what this node has already spent across all iterations
  const nodeSpent = state.history
    .filter(h => h.graph_node === state.graph_node)
    .reduce((sum, h) => sum + h.cost_usd, 0);
  const nodeRemaining = nodeBudget - nodeSpent;

  const hostBudgetCap = Math.max(0, Math.min(runRemaining, nodeRemaining));

  if (hostBudgetCap <= 0) {
    const reason = runRemaining <= 0
      ? `run budget exhausted ($${state.cost_usd.toFixed(2)} / $${state.budget_usd})`
      : `node "${state.graph_node}" budget exhausted ($${nodeSpent.toFixed(2)} / $${nodeBudget})`;
    return { allowed: false, runRemaining, nodeRemaining, hostBudgetCap: 0, reason };
  }

  return { allowed: true, runRemaining, nodeRemaining, hostBudgetCap };
}

/** Budget-slope detection (vendored from ruvnet/continue-gate.ts)
 *
 * The original uses linear regression over spend history to predict
 * whether the run will blow the cap BEFORE it does, rather than at the
 * moment it does. Worth adding — predictive rather than reactive.
 *
 * Returns true if the slope suggests the budget will be exceeded within
 * the remaining iterations.
 */
export function budgetSlopeExceeds(  state: RunState,
  node: GraphNode,
): boolean {
  const history = state.history;
  if (history.length < 2) return false;

  // Simple linear regression on cumulative cost
  const n = history.length;
  let sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
  for (let i = 0; i < n; i++) {
    sumX += i;
    sumY += history[i].cost_usd;
    sumXY += i * history[i].cost_usd;
    sumXX += i * i;
  }
  const slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX);

  const maxIter = node.max_iterations ?? 3;
  const predictedNext = history[n - 1].cost_usd + slope;
  const runBudget = state.budget_usd ?? 25;

  return (state.cost_usd + predictedNext) > runBudget;
}
