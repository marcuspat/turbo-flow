import type { HostAdapter, HostExecuteResult } from './adapter.js';
export declare class ClaudeAdapter implements HostAdapter {
    readonly name = "claude";
    readonly supportsCLIBudgetCap = true;
    execute(opts: {
        prompt: string;
        model: string;
        maxBudgetUsd: number;
        maxTurns?: number;
        permissionMode?: string;
        allowedTools?: string;
        jsonSchema?: object;
        resumeSession?: string;
        cwd: string;
    }): Promise<HostExecuteResult>;
    judge(opts: {
        rubric: string;
        content: string;
        model: string;
        maxBudgetUsd: number;
        cwd: string;
    }): Promise<HostExecuteResult>;
    private runClaude;
}
/** Create the adapter (factory for future host switching) */
export declare function createHostAdapter(hostName?: string): HostAdapter;
//# sourceMappingURL=claude.d.ts.map