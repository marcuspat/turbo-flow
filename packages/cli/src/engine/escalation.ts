// ─── Escalation ─────────────────────────────────────────
// The thing nobody else in the ecosystem ships.

import { execFileSync } from 'node:child_process';
import type { RunState } from '../schemas/state.js';
import { writeState, readState, setActive } from '../schemas/state.js';

export interface EscalationResult {
  escalated: boolean;
  channel: string;
  issueUrl?: string;
  issueNumber?: number;
}

/** Escalate to human via the configured channel */
export async function escalate(
  state: RunState,
  question: string,
  opts: {
    repoRoot: string;
    mention?: string;
    channel?: 'github_issue' | 'notification';
  },
): Promise<EscalationResult> {
  const channel = opts.channel ?? 'github_issue';

  if (channel === 'github_issue') {
    return escalateViaGithub(state, question, opts);
  }

  // Notification channel — just mark state, the desktop/session hook handles the rest
  state.status = 'awaiting_human';
  state.escalation.question = question;
  state.escalation.timestamp = new Date().toISOString();
  writeState(state, opts.repoRoot);
  setActive(null, opts.repoRoot);

  return { escalated: true, channel: 'notification' };
}

async function escalateViaGithub(
  state: RunState,
  question: string,
  opts: { repoRoot: string; mention?: string },
): Promise<EscalationResult> {
  const body = [
    '## turbo-flow needs a decision',
    '',
    `**Spec:** \`${state.spec}\``,
    `**Node:** \`${state.graph_node}\``,
    `**Iteration:** ${state.node_iteration}`,
    `**Cost so far:** $${state.cost_usd.toFixed(2)} / $${state.budget_usd}`,
    '',
    '---',
    '',
    question,
    '',
    '---',
    '',
    `Reply with: /tf answer ${state.spec} <your decision>`,
    '',
    `Or run locally: turbo-flow answer ${state.spec} "<your decision>"`,
  ].join('\n');

  const mention = opts.mention ? `\n\ncc @${opts.mention}` : '';
  const title = `tf: needs decision — ${state.spec} @ ${state.graph_node}`;

  let issueNumber: number | undefined;
  let issueUrl: string | undefined;

  try {
    const result = execFileSync(
      'gh',
      ['issue', 'create', '--title', title, '--body', body + mention, '--label', 'tf'],
      { cwd: opts.repoRoot, encoding: 'utf-8', timeout: 30_000, env: { ...process.env } },
    ).trim();

    issueUrl = result;
    const match = result.match(/\/(\d+)$/);
    if (match) issueNumber = parseInt(match[1], 10);
  } catch (err: unknown) {
    const e = err as { message?: string };
    const msg = `gh not available (${e.message ?? 'unknown'}). Escalating via notification.`;
    process.stderr.write(`turbo-flow: warn: ${msg}\n`);
  }

  state.status = 'awaiting_human';
  state.escalation.question = question;
  state.escalation.issue_url = issueUrl ?? null;
  state.escalation.issue_number = issueNumber ?? null;
  state.escalation.timestamp = new Date().toISOString();
  writeState(state, opts.repoRoot);
  setActive(null, opts.repoRoot);

  return { escalated: true, channel: 'github_issue', issueUrl, issueNumber };
}

/** Record a human answer and mark the run for resumption */
export function recordAnswer(
  specId: string,
  answer: string,
  repoRoot: string,
): RunState | null {
  const state = readState(specId, repoRoot);
  if (!state) {
    process.stderr.write(`turbo-flow: no active run for ${specId}\n`);
    return null;
  }

  if (state.status !== 'awaiting_human') {
    process.stderr.write(`turbo-flow: ${specId} is not awaiting human input (status: ${state.status})\n`);
    return state;
  }

  state.escalation.answer = answer;
  state.escalation.resolved_at = new Date().toISOString();
  state.status = 'running';
  writeState(state, repoRoot);
  setActive(specId, repoRoot);

  return state;
}
