import type { RunState } from '../schemas/state.js';
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
export declare function checkBudget(state: RunState, node: GraphNode): BudgetCheck;
/** Budget-slope detection (vendored from ruvnet/continue-gate.ts)
 *
 * The original uses linear regression over spend history to predict
 * whether the run will blow the cap BEFORE it does, rather than at the
 * moment it does. Worth adding — predictive rather than reactive.
 *
 * Returns true if the slope suggests the budget will be exceeded within
 * the remaining iterations.
 */
export declare function budgetSlopeExceeds(state: RunState, node: GraphNode): boolean;
//# sourceMappingURL=budget.d.ts.map