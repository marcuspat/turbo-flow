// ─── Run state schema ────────────────────────────────────────────────
// Compatible with the bash lg engine's state.json format.
// This IS the compatibility contract.

import { readFileSync, writeFileSync, mkdirSync, existsSync, unlinkSync } from 'node:fs';
import { dirname } from 'node:path';

/** Typed termination reasons — vendored concept from metaharness/scheduler.ts */
export type TerminationReason =
  | 'success'
  | 'budget_exhausted'
  | 'max_retries'
  | 'max_escalations'
  | 'max_cycles'
  | 'max_transitions'
  | 'context_overflow'
  | 'security_uncertain'
  | 'needs_human'
  | 'failed'
  | 'aborted';

export type RunStatus =
  | 'running'
  | 'awaiting_human'
  | 'completed'
  | 'failed'
  | 'budget_exceeded'
  | 'aborted';

export interface EscalationState {
  question: string | null;
  answer: string | null;
  issue_url: string | null;
  issue_number: number | null;
  timestamp: string | null;
  resolved_at: string | null;
}

export interface GateResult {
  id: string;
  type: 'cmd' | 'judge';
  passed: boolean;
  feedback?: string;
  verdict?: import('./verdict.js').Verdict;
  duration_ms: number;
  skipped?: boolean;
  skip_reason?: string;
}

export interface NodeIteration {
  iteration: number;
  graph_node: string;
  session_id: string | null;
  model: string;
  cost_usd: number;
  turns: number;
  gates: GateResult[];
  passed: boolean;
  halted_reason: string | null;
}

export interface RunState {
  spec: string;
  graph_node: string;
  status: RunStatus;
  budget_usd: number;
  cost_usd: number;
  iteration: number;
  node_iteration: number;
  max_cycles: number;
  cycles_used: number;
  transitions: number;
  model: string;
  branch: string;
  started_at: string;
  updated_at: string;
  completed_at: string | null;
  termination_reason: TerminationReason | null;
  escalation: EscalationState;
  history: NodeIteration[];
  /** Transient: human answer from escalation, consumed on next node execution */
  _human_answer?: string;
  /** Transient: gate feedback from failed gates, fed back on retry */
  _gate_feedback?: string;
}

/** Create initial state for a new run */
export function createInitialState(spec: string, graphEntry: string, opts: {
  budgetUsd: number;
  model: string;
  branch: string;
  maxCycles?: number;
}): RunState {
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
export function statePath(specId: string, repoRoot: string): string {
  return `${repoRoot}/${STATE_DIR}/${specId}/state.json`;
}

/** Read state from disk */
export function readState(specId: string, repoRoot: string): RunState | null {
  const p = statePath(specId, repoRoot);
  if (!existsSync(p)) return null;
  return JSON.parse(readFileSync(p, 'utf-8')) as RunState;
}

/** Write state to disk, creating directories as needed */
export function writeState(state: RunState, repoRoot: string): void {
  const p = statePath(state.spec, repoRoot);
  mkdirSync(dirname(p), { recursive: true });
  state.updated_at = new Date().toISOString();
  writeFileSync(p, JSON.stringify(state, null, 2) + '\n', 'utf-8');
}

/** Set the active spec marker */
export function setActive(specId: string | null, repoRoot: string): void {
  const markerPath = `${repoRoot}/${STATE_DIR.replace('/runs', '')}/active`;
  const dir = dirname(markerPath);
  mkdirSync(dir, { recursive: true });
  if (specId === null) {
    if (existsSync(markerPath)) unlinkSync(markerPath);
    return;
  }
  writeFileSync(markerPath, specId, 'utf-8');
}

export { STATE_DIR };
