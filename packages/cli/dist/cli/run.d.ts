export declare function runCommand(specId: string, opts: {
    step?: boolean;
    resume?: boolean;
    budget?: string;
}): Promise<void>;
declare function formatResult(result: {
    exitCode: number;
    message: string;
    state: any;
}): string;
export { formatResult };
//# sourceMappingURL=run.d.ts.map