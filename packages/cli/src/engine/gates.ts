// ─── Gate runner ─────────────────────────────────────────────────
// Deterministic gates (cmd) cost nothing. Judge gates cost money.
// Deterministic gates run first, always. Never pay a model to check
// something test(1) can check.

import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import type { Gate, GraphNode } from '../schemas/graph.js';
import type { Verdict } from '../schemas/verdict.js';
import { validateVerdict, VERDICT_SCHEMA } from '../schemas/verdict.js';
import type { HostAdapter } from '../host/adapter.js';
import type { GateResult } from '../schemas/state.js';

export interface GateRunResult {
  passed: boolean;
  results: GateResult[];
  /** Feedback to feed back into the node on failure */
  feedback: string;
  /** If a gate set needs_human */
  needsHuman: boolean;
  /** The human question, if any */
  question: string | null;
}

/** Run all gates for a node. Cmd gates first, then judge gates. */
export async function runGates(
  node: GraphNode,
  lastOutput: string,
  host: HostAdapter,
  opts: {
    specId: string;
    repoRoot: string;
    model: string;
    maxBudgetUsd: number;
  },
): Promise<GateRunResult> {
  const gates = node.gates ?? [];
  const cmdGates = gates.filter(g => g.type === 'cmd');
  const judgeGates = gates.filter(g => g.type === 'judge');

  const results: GateResult[] = [];
  let feedback = '';
  let needsHuman = false;
  let question: string | null = null;
  let anyFailed = false;

  // ── Deterministic gates first ──────────────────────────────────
  for (const gate of cmdGates) {
    const start = Date.now();
    const result = runCmdGate(gate, opts.repoRoot, opts.specId);
    results.push(result);

    if (!result.passed) {
      anyFailed = true;
      feedback += `### Gate failed: \`${gate.run}\`\n\n\`\`\`\n${result.feedback}\n\`\`\`\n\n`;
    }
  }

  // ── Judge gates only if all cmd gates passed ────────────────────
  if (!anyFailed) {
    for (const gate of judgeGates) {
      const start = Date.now();
      const result = await runJudgeGate(
        gate, lastOutput, host, opts,
      );
      results.push(result);

      if (!result.passed) {
        anyFailed = true;
        if (result.verdict?.blocking) {
          feedback += '### Judge gate failed: `' + (gate.rubric ?? gate.id) + '`\n\n';
          for (const b of result.verdict.blocking) {
            feedback += `- ${b}\n`;
          }
          feedback += '\n';
        }
      }

      if (result.verdict?.needs_human) {
        needsHuman = true;
        question = result.verdict.question ?? null;
      }
    }
  }

  return { passed: !anyFailed, results, feedback, needsHuman, question };
}

/** Run a deterministic (cmd) gate */
export function runCmdGate(
  gate: Gate,
  repoRoot: string,
  specId: string,
): GateResult {
  const start = Date.now();
  const cmd = (gate.run ?? '')
    .replace(/\$\{SPEC_ID\}/g, specId);

  // Optional gates: skip if the command/file doesn't exist
  if (gate.optional_if_absent) {
    const cmdBinary = cmd.split(/\s+/)[0];
    if (cmdBinary && !existsSync(`${repoRoot}/${cmdBinary}`) && !existsSync(cmdBinary)) {
      return {
        id: gate.id,
        type: 'cmd',
        passed: true,
        skipped: true,
        skip_reason: `optional gate: ${cmdBinary} not found`,
        duration_ms: Date.now() - start,
      };
    }
  }

  try {
    execFileSync('bash', ['-c', cmd], {
      cwd: repoRoot,
      timeout: 5 * 60 * 1000, // 5 min per gate
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env, SPEC_ID: specId },
    });
    return { id: gate.id, type: 'cmd', passed: true, duration_ms: Date.now() - start };
  } catch (err: unknown) {
    const e = err as { stderr?: string | Buffer; status?: number };
    const stderr = (e.stderr instanceof Buffer ? e.stderr.toString() : String(e.stderr ?? ''))
      .slice(0, 4000);
    return {
      id: gate.id,
      type: 'cmd',
      passed: false,
      feedback: stderr || `exit code ${e.status ?? 1}`,
      duration_ms: Date.now() - start,
    };
  }
}

/** Run a judge gate — model evaluates against rubric */
async function runJudgeGate(
  gate: Gate,
  content: string,
  host: HostAdapter,
  opts: {
    specId: string;
    repoRoot: string;
    model: string;
    maxBudgetUsd: number;
  },
): Promise<GateResult & { verdict?: Verdict }> {
  const start = Date.now();
  const rubricPath = `${opts.repoRoot}/${gate.rubric ?? ''}`;

  // Read the rubric file
  let rubric: string;
  try {
    const { readFileSync } = await import('node:fs');
    rubric = readFileSync(rubricPath, 'utf-8');
  } catch {
    return {
      id: gate.id,
      type: 'judge',
      passed: false,
      feedback: `rubric file not found: ${rubricPath}`,
      duration_ms: Date.now() - start,
    };
  }

  const model = gate.model || opts.model;

  // Truncate content for judge to avoid blowing budget on re-reading code
  const truncatedContent = content.length > 50000
    ? content.slice(0, 50000) + '\n\n[... truncated at 50K chars ...]'
    : content;

  const result = await host.judge({
    rubric,
    content: truncatedContent,
    model,
    maxBudgetUsd: Math.min(opts.maxBudgetUsd, 5), // Cap judge spend at $5
    cwd: opts.repoRoot,
  });

  if (result.error) {
    return {
      id: gate.id,
      type: 'judge',
      passed: false,
      feedback: `judge invocation failed: ${result.error}`,
      duration_ms: Date.now() - start,
    };
  }

  // Parse verdict from result
  let verdict: Verdict;
  try {
    const jsonMatch = result.result_text.match(/\{[\s\S]*\}/);
    if (!jsonMatch) throw new Error('no JSON found in output');
    verdict = JSON.parse(jsonMatch[0]) as Verdict;
  } catch {
    return {
      id: gate.id,
      type: 'judge',
      passed: false,
      feedback: `judge did not return valid JSON verdict: ${result.result_text.slice(0, 500)}`,
      duration_ms: Date.now() - start,
    };
  }

  // Re-validate the verdict
  const validation = validateVerdict(verdict);
  if (!validation.valid) {
    return {
      id: gate.id,
      type: 'judge',
      passed: false,
      feedback: `verdict validation failed: ${validation.errors.join('; ')}`,
      duration_ms: Date.now() - start,
    };
  }

  return {
    id: gate.id,
    type: 'judge',
    passed: verdict.pass,
    verdict,
    duration_ms: Date.now() - start,
  };
}
