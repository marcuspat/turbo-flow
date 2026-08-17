// ─── turbo-flow run ─────────────────────────────────────────

import { runEngine, EXIT } from '../engine/engine.js';
import { join } from 'node:path';

export async function runCommand(specId: string, opts: {
  step?: boolean;
  resume?: boolean;
  budget?: string;
}) {
  const repoRoot = process.cwd();

  // Apply budget override if specified
  if (opts.budget) {
    const { readState, writeState } = await import('../schemas/state.js');
    const state = readState(specId, repoRoot);
    if (state) {
      const budget = parseFloat(opts.budget);
      if (isNaN(budget)) {
        console.error('turbo-flow: --budget must be a number');
        process.exit(1);
      }
      state.budget_usd = budget;
      writeState(state, repoRoot);
      console.log(`turbo-flow: budget overridden to $${budget}`);
    }
  }

  const result = await runEngine({
    repoRoot,
    specId,
    singleStep: opts.step,
    resume: opts.resume,
  });

  // Pretty print result
  console.log(formatResult(result));

  process.exit(result.exitCode);
}

function formatResult(result: { exitCode: number; message: string; state: any }): string {
  const lines: string[] = [''];

  if (result.state) {
    const s = result.state;
    lines.push(`  spec:     ${s.spec}`);
    lines.push(`  node:     ${s.graph_node}`);
    lines.push(`  status:   ${s.status}`);
    lines.push(`  cost:     $${s.cost_usd.toFixed(2)} / $${s.budget_usd}`);
    lines.push(`  iter:     ${s.node_iteration}`);
    lines.push(`  cycles:   ${s.cycles_used}`);
    if (s.escalation?.question) {
      lines.push(`  waiting:  ${s.escalation.question}`);
    }
  }

  lines.push('');
  lines.push(`  ${result.message}`);
  lines.push('');

  return lines.join('\n');
}

export { formatResult };
