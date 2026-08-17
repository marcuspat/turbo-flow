// ─── turbo-flow answer ───────────────────────────────────
import { recordAnswer } from '../engine/escalation.js';
export async function answerCommand(specId, answer) {
    const repoRoot = process.cwd();
    const state = recordAnswer(specId, answer, repoRoot);
    if (!state) {
        process.exit(1);
    }
    console.log(`turbo-flow: answer recorded for ${specId}`);
    console.log(`turbo-flow: run 'turbo-flow run ${specId}' to resume`);
}
//# sourceMappingURL=answer.js.map