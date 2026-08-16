// ─── Host adapter interface ──────────────────────────────────────────
// One interface, many hosts. The engine never knows which host is running
// a node — it just calls execute() and gets back a result.

import type { Verdict } from '../schemas/verdict.js';

export interface HostExecuteResult {
  /** The model's text output */
  result_text: string;
  /** Cost in USD reported by the CLI */
  cost_usd: number;
  /** Session ID for resume */
  session_id: string | null;
  /** Number of turns consumed */
  turns: number;
  /** If the host hit an error */
  error?: string;
}

export interface HostAdapter {
  /** The host name (for logging and graph.json matching) */
  readonly name: string;

  /**
   * Execute a prompt through this host.
   */
  execute(opts: {
    prompt: string;
    model: string;
    maxBudgetUsd: number;
    maxTurns?: number;
    permissionMode?: string;
    allowedTools?: string;
    jsonSchema?: object;
    resumeSession?: string;
    cwd: string;
  }): Promise<HostExecuteResult>;

  /**
   * Execute a judge gate — run a rubric against content and get a structured verdict.
   */
  judge(opts: {
    rubric: string;
    content: string;
    model: string;
    maxBudgetUsd: number;
    cwd: string;
  }): Promise<HostExecuteResult>;

  /** Whether this host supports mid-turn budget enforcement via CLI flag */
  readonly supportsCLIBudgetCap: boolean;
}
