export interface Verdict {
    pass: boolean;
    blocking: string[];
    non_blocking?: string[];
    not_verified?: string[];
    needs_human: boolean;
    question?: string;
    evidence: string[];
}
/** JSON Schema for verdict — passed to --json-schema / --output-schema */
export declare const VERDICT_SCHEMA: {
    readonly type: "object";
    readonly additionalProperties: false;
    readonly properties: {
        readonly pass: {
            readonly type: "boolean";
            readonly description: "true only if every blocking criterion in the rubric is satisfied with evidence. Absence of evidence is not pass.";
        };
        readonly blocking: {
            readonly type: "array";
            readonly items: {
                readonly type: "string";
            };
            readonly description: "Things that must be fixed before this node can advance. Each entry must be specific enough to act on without asking a follow-up question: name the file, the symbol, the command, the observed vs expected behaviour.";
        };
        readonly non_blocking: {
            readonly type: "array";
            readonly items: {
                readonly type: "string";
            };
            readonly description: "Real issues that do not justify another loop iteration.";
        };
        readonly not_verified: {
            readonly type: "array";
            readonly items: {
                readonly type: "string";
            };
            readonly description: "Criteria you could not check, and why. Never imply coverage you do not have.";
        };
        readonly needs_human: {
            readonly type: "boolean";
            readonly description: "true when the blocker is a DECISION rather than a DEFECT — a product/scope/tradeoff/credentials call the agent must not make unilaterally.";
        };
        readonly question: {
            readonly type: "string";
            readonly description: "When needs_human is true: one sentence, phrased as a concrete choice with the options named.";
        };
        readonly evidence: {
            readonly type: "array";
            readonly items: {
                readonly type: "string";
            };
            readonly description: "What you actually inspected — file paths, commands run, diffs read. Required on pass as well as fail.";
        };
    };
    readonly required: readonly ["pass", "blocking", "needs_human", "evidence"];
};
/** Validate a verdict object against the schema */
export declare function validateVerdict(v: unknown): {
    valid: boolean;
    errors: string[];
};
//# sourceMappingURL=verdict.d.ts.map