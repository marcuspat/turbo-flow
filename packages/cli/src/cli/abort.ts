// ─── turbo-flow abort ───────────────────────────────────

import { readState, writeState, setActive } from '../schemas/state.js';

export async function abortCommand(specId: string, reason?: string) {
  const repoRoot = process.cwd();
  const state = readState(specId, repoRoot);

  if (!state) {
    console.error(`turbo-flow: no active run for ${specId}`);
    process.exit(1);
  }

  state.status = 'aborted';
  state.termination_reason = 'aborted';
  state.completed_at = new Date().toISOString();
  writeState(state, repoRoot);
  setActive(null, repoRoot);

  console.log(`turbo-flow: ${specId} aborted — $${state.cost_usd.toFixed(2)} spent`);
  if (reason) console.log(`  reason: ${reason}`);
}