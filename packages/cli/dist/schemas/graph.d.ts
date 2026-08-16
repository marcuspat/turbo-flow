/** Which host runs a node. Extend for codex, etc. */
export type HostName = 'claude';
/** Gate types */
export type GateType = 'cmd' | 'judge';
/** A single gate on a node */
export interface Gate {
    id: string;
    type: GateType;
    run?: string;
    rubric?: string;
    model?: string;
    optional_if_absent?: boolean;
    _why?: string;
}
/** A node in the graph */
export interface GraphNode {
    _purpose?: string;
    prompt?: string;
    model?: string;
    max_iterations?: number;
    budget_usd?: number;
    max_turns?: number;
    permission_mode?: string;
    allowed_tools?: string;
    writes?: string[];
    gates?: Gate[];
    on_pass?: string;
    on_fail?: string;
    terminal?: boolean;
    escalates?: boolean;
    agent?: string;
    host?: HostName;
    _note?: string;
    [key: string]: unknown;
}
/** Escalation configuration */
export interface EscalationConfig {
    channel: 'github_issue' | 'notification';
    mention?: string;
}
/** The graph definition */
export interface Graph {
    version: number;
    name: string;
    budget_usd?: number;
    default_model?: string;
    escalation?: EscalationConfig;
    entry: string;
    nodes: Record<string, GraphNode>;
}
/** Parse and validate graph.json */
export declare function loadGraph(filePath: string): Graph;
/** Validate graph structure — all edges land on real nodes */
export declare function validateGraph(graph: Graph): string[];
/** Find cycle pairs for max_cycles enforcement */
export declare function findCycles(graph: Graph): [string, string][];
//# sourceMappingURL=graph.d.ts.map