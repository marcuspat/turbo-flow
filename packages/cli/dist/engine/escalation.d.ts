import type { RunState } from '../schemas/state.js';
export interface EscalationResult {
    escalated: boolean;
    channel: string;
    issueUrl?: string;
    issueNumber?: number;
}
/** Escalate to human via the configured channel */
export declare function escalate(state: RunState, question: string, opts: {
    repoRoot: string;
    mention?: string;
    channel?: 'github_issue' | 'notification';
}): Promise<EscalationResult>;
/** Record a human answer and mark the run for resumption */
export declare function recordAnswer(specId: string, answer: string, repoRoot: string): RunState | null;
//# sourceMappingURL=escalation.d.ts.map