/** Typed termination reasons — vendored concept from metaharness/scheduler.ts */
export type TerminationReason = 'success' | 'budget_exhausted' | 'max_retries' | 'max_escalations' | 'max_cycles' | 'max_transitions' | 'context_overflow' | 'security_uncertain' | 'needs_human' | 'failed' | 'aborted';
export type RunStatus = 'running' | 'awaiting_human' | 'completed' | 'failed' | 'budget_exceeded' | 'aborted';
export interface EscalationState {
    question: string | null;
    answer: string | null;
    issue_url: string | null;
    issue_number: number | null;
    timestamp: string | null;
    resolved_at: string | null;
}
export interface GateResult {
    id: string;
    type: 'cmd' | 'judge';
    passed: boolean;
    feedback?: string;
    verdict?: import('./verdict.js').Verdict;
    duration_ms: number;
    skipped?: boolean;
    skip_reason?: string;
}
export interface NodeIteration {
    iteration: number;
    graph_node: string;
    session_id: string | null;
    model: string;
    cost_usd: number;
    turns: number;
    gates: GateResult[];
    passed: boolean;
    halted_reason: string | null;
}
export interface RunState {
    spec: string;
    graph_node: string;
    status: RunStatus;
    budget_usd: number;
    cost_usd: number;
    iteration: number;
    node_iteration: number;
    max_cycles: number;
    cycles_used: number;
    transitions: number;
    model: string;
    branch: string;
    started_at: string;
    updated_at: string;
    completed_at: string | null;
    termination_reason: TerminationReason | null;
    escalation: EscalationState;
    history: NodeIteration[];
    /** Transient: human answer from escalation, consumed on next node execution */
    _human_answer?: string;
    /** Transient: gate feedback from failed gates, fed back on retry */
    _gate_feedback?: string;
}
/** Create initial state for a new run */
export declare function createInitialState(spec: string, graphEntry: string, opts: {
    budgetUsd: number;
    model: string;
    branch: string;
    maxCycles?: number;
}): RunState;
declare const STATE_DIR = ".lg/runs";
/** Get the path to a spec's state file */
export declare function statePath(specId: string, repoRoot: string): string;
/** Read state from disk */
export declare function readState(specId: string, repoRoot: string): RunState | null;
/** Write state to disk, creating directories as needed */
export declare function writeState(state: RunState, repoRoot: string): void;
/** Set the active spec marker */
export declare function setActive(specId: string | null, repoRoot: string): void;
export { STATE_DIR };
//# sourceMappingURL=state.d.ts.map