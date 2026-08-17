import type { Gate, GraphNode } from '../schemas/graph.js';
import type { HostAdapter } from '../host/adapter.js';
import type { GateResult } from '../schemas/state.js';
export interface GateRunResult {
    passed: boolean;
    results: GateResult[];
    /** Feedback to feed back into the node on failure */
    feedback: string;
    /** If a gate set needs_human */
    needsHuman: boolean;
    /** The human question, if any */
    question: string | null;
}
/** Run all gates for a node. Cmd gates first, then judge gates. */
export declare function runGates(node: GraphNode, lastOutput: string, host: HostAdapter, opts: {
    specId: string;
    repoRoot: string;
    model: string;
    maxBudgetUsd: number;
}): Promise<GateRunResult>;
/** Run a deterministic (cmd) gate */
export declare function runCmdGate(gate: Gate, repoRoot: string, specId: string): GateResult;
//# sourceMappingURL=gates.d.ts.map