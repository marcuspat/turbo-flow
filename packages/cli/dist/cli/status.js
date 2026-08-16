// ─── turbo-flow status ─────────────────────────────────────
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
export async function statusCommand(specId) {
    const repoRoot = process.cwd();
    const runsDir = join(repoRoot, '.lg', 'runs');
    if (!existsSync(runsDir)) {
        console.log('turbo-flow: no runs found');
        return;
    }
    if (specId) {
        const statePath = join(runsDir, specId, 'state.json');
        if (!existsSync(statePath)) {
            console.error(`turbo-flow: no run state for ${specId}`);
            process.exit(1);
        }
        const state = JSON.parse(readFileSync(statePath, 'utf-8'));
        printState(state);
        return;
    }
    // List all runs
    const specs = readdirSync(runsDir).filter(s => {
        return existsSync(join(runsDir, s, 'state.json'));
    });
    if (specs.length === 0) {
        console.log('turbo-flow: no runs found');
        return;
    }
    for (const spec of specs) {
        const statePath = join(runsDir, spec, 'state.json');
        const state = JSON.parse(readFileSync(statePath, 'utf-8'));
        printState(state);
        console.log('');
    }
}
function printState(s) {
    const statusIcon = {
        running: '▶',
        awaiting_human: '⏸',
        completed: '✓',
        failed: '✗',
        budget_exceeded: '💰',
        aborted: '⊘',
    };
    const icon = statusIcon[s.status] ?? '?';
    const waiting = s.escalation?.answer == null && s.escalation?.question
        ? `  ⟵ WAITING: ${s.escalation.question}`
        : '';
    console.log(`  ${icon} \`${s.spec}\` — ${s.graph_node} — ${s.status} — $${s.cost_usd.toFixed(2)}/${s.budget_usd}${waiting}`);
    if (s.history.length > 0) {
        for (const h of s.history) {
            const passed = h.passed ? 'PASS' : 'FAIL';
            const gates = h.gates?.map(g => `${g.passed ? '✓' : '✗'}${g.id}`).join(' ') ?? '';
            console.log(`    iter ${h.iteration}: ${h.model} $${h.cost_usd.toFixed(2)} ${h.turns}t ${passed} ${gates}`);
        }
    }
}
//# sourceMappingURL=status.js.map