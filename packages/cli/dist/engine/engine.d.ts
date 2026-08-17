import { type RunState } from '../schemas/state.js';
export declare const EXIT: {
    readonly OK: 0;
    readonly AWAITING_HUMAN: 10;
    readonly BUDGET_EXCEEDED: 20;
    readonly FAILED: 30;
    readonly ERROR: 1;
};
export declare const MAX_TRANSITIONS = 40;
export interface EngineOpts {
    repoRoot: string;
    specId: string;
    singleStep?: boolean;
    resume?: boolean;
}
export interface EngineResult {
    exitCode: typeof EXIT[keyof typeof EXIT];
    state: RunState;
    message: string;
}
/**
 * Run the engine — the main entry point.
 * Returns when the run is terminal, awaiting human, or after one step.
 */
export declare function runEngine(opts: EngineOpts): Promise<EngineResult>;
//# sourceMappingURL=engine.d.ts.map