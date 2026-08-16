// ─── Run state schema ────────────────────────────────────────────────
// Compatible with the bash lg engine's state.json format.
// This IS the compatibility contract.
import { readFileSync, writeFileSync, mkdirSync, existsSync, unlinkSync } from 'node:fs';
import { dirname } from 'node:path';
/** Create initial state for a new run */
export function createInitialState(spec, graphEntry, opts) {
    const now = new Date().toISOString();
    return {
        spec,
        graph_node: graphEntry,
        status: 'running',
        budget_usd: opts.budgetUsd,
        cost_usd: 0,
        iteration: 0,
        node_iteration: 0,
        max_cycles: opts.maxCycles ?? 3,
        cycles_used: 0,
        transitions: 0,
        model: opts.model,
        branch: opts.branch,
        started_at: now,
        updated_at: now,
        completed_at: null,
        termination_reason: null,
        escalation: {
            question: null,
            answer: null,
            issue_url: null,
            issue_number: null,
            timestamp: null,
            resolved_at: null,
        },
        history: [],
    };
}
const STATE_DIR = '.lg/runs';
/** Get the path to a spec's state file */
export function statePath(specId, repoRoot) {
    return `${repoRoot}/${STATE_DIR}/${specId}/state.json`;
}
/** Read state from disk */
export function readState(specId, repoRoot) {
    const p = statePath(specId, repoRoot);
    if (!existsSync(p))
        return null;
    return JSON.parse(readFileSync(p, 'utf-8'));
}
/** Write state to disk, creating directories as needed */
export function writeState(state, repoRoot) {
    const p = statePath(state.spec, repoRoot);
    mkdirSync(dirname(p), { recursive: true });
    state.updated_at = new Date().toISOString();
    writeFileSync(p, JSON.stringify(state, null, 2) + '\n', 'utf-8');
}
/** Set the active spec marker */
export function setActive(specId, repoRoot) {
    const markerPath = `${repoRoot}/${STATE_DIR.replace('/runs', '')}/active`;
    const dir = dirname(markerPath);
    mkdirSync(dir, { recursive: true });
    if (specId === null) {
        if (existsSync(markerPath))
            unlinkSync(markerPath);
        return;
    }
    writeFileSync(markerPath, specId, 'utf-8');
}
export { STATE_DIR };
//# sourceMappingURL=state.js.map