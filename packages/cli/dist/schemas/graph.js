// ─── Graph schema types ─────────────────────────────────────────────────
// One file is the whole control surface: change what the harness does by
// editing graph.json, not by editing the engine.
import { readFileSync } from 'node:fs';
/** Parse and validate graph.json */
export function loadGraph(filePath) {
    const raw = readFileSync(filePath, 'utf-8');
    return JSON.parse(raw);
}
/** Validate graph structure — all edges land on real nodes */
export function validateGraph(graph) {
    const errors = [];
    const nodeKeys = Object.keys(graph.nodes);
    if (!nodeKeys.includes(graph.entry)) {
        errors.push(`entry "${graph.entry}" is not a defined node`);
    }
    for (const [key, node] of Object.entries(graph.nodes)) {
        if (node.terminal)
            continue;
        const checkEdge = (edge, label) => {
            if (!edge)
                return;
            if (!nodeKeys.includes(edge)) {
                errors.push(`node "${key}" ${label} "${edge}" is not a defined node`);
            }
        };
        checkEdge(node.on_pass, 'on_pass');
        checkEdge(node.on_fail, 'on_fail');
    }
    return errors;
}
/** Find cycle pairs for max_cycles enforcement */
export function findCycles(graph) {
    const cycles = [];
    for (const [key, node] of Object.entries(graph.nodes)) {
        if (node.on_fail && node.on_fail !== key) {
            const target = graph.nodes[node.on_fail];
            if (target?.on_pass === key) {
                cycles.push([key, node.on_fail]);
            }
        }
    }
    return cycles;
}
//# sourceMappingURL=graph.js.map