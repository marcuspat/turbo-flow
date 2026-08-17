// ─── Engine — the graph interpreter ──────────────────────────────────
// One spec goes in. The graph runs it. You get pinged only when a
// decision is genuinely yours.
//
// The graph (graph.json) is the control flow. This file is the interpreter.
// You should almost never need to edit this file to change behaviour.

import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import type { Graph, GraphNode } from '../schemas/graph.js';
import { loadGraph, validateGraph, findCycles } from '../schemas/graph.js';
import { createInitialState, readState, writeState, setActive, type RunState } from '../schemas/state.js';
import { checkBudget, budgetSlopeExceeds } from './budget.js';
import { runGates, type GateRunResult } from './gates.js';
import { escalate } from './escalation.js';
import { createHostAdapter } from '../host/claude.js';
import type { HostAdapter } from '../host/adapter.js';

// Exit codes — compatible with bash lg
export const EXIT = {
  OK: 0,
  AWAITING_HUMAN: 10,
  BUDGET_EXCEEDED: 20,
  FAILED: 30,
  ERROR: 1,
} as const;

export const MAX_TRANSITIONS = 40;

export interface EngineOpts {
  repoRoot: string;
  specId: string;
  singleStep?: boolean;
  resume?: boolean;
}

export interface EngineResult {
  exitCode: typeof EXIT[keyof typeof EXIT];
  state: RunState;
  message: string;
}

/**
 * Run the engine — the main entry point.
 * Returns when the run is terminal, awaiting human, or after one step.
 */
export async function runEngine(opts: EngineOpts): Promise<EngineResult> {
  const { repoRoot, specId } = opts;

  // Load graph
  const graphPath = join(repoRoot, 'graph.json');
  let graph: Graph;
  try {
    graph = loadGraph(graphPath);
  } catch (err) {
    return { exitCode: EXIT.ERROR, state: null as any, message: `failed to load graph.json: ${err}` };
  }

  const errors = validateGraph(graph);
  if (errors.length > 0) {
    return { exitCode: EXIT.ERROR, state: null as any, message: `graph validation failed:\n${errors.join('\n')}` };
  }

  const cycles = findCycles(graph);

  // Load or create state
  let state = readState(specId, repoRoot);
  if (!state) {
    if (opts.resume) {
      return { exitCode: EXIT.ERROR, state: null as any, message: `no run state found for ${specId}` };
    }
    const specPath = join(repoRoot, 'specs', `${specId}.md`);
    if (!existsSync(specPath)) {
      return { exitCode: EXIT.ERROR, state: null as any, message: `spec not found: specs/${specId}.md` };
    }

    state = createInitialState(specId, graph.entry, {
      budgetUsd: graph.budget_usd ?? 25,
      model: graph.default_model ?? 'claude-sonnet-4-20250514',
      branch: `lg/${specId}`,
    });
    writeState(state, repoRoot);
    setActive(specId, repoRoot);
  }

  // If awaiting human and not resuming with an answer, just report
  if (state.status === 'awaiting_human') {
    if (!state.escalation.answer) {
      return {
        exitCode: EXIT.AWAITING_HUMAN,
        state,
        message: `awaiting human decision: ${state.escalation.question}`,
      };
    }
    // Human answered — clear the escalation and continue
    const answer = state.escalation.answer;
    state.escalation.resolved_at = new Date().toISOString();
    state.status = 'running';
    state.escalation.answer = null;
    // Store the answer for the next node execution
    state._human_answer = answer;
    writeState(state, repoRoot);
  }

  const host = createHostAdapter('claude');

  // Set TF_ENGINE=1 so Stop hooks know the engine is driving.
  // This prevents hook-side gate execution — the engine runs gates itself.
  process.env.TF_ENGINE = '1';

  // Main loop
  while (state.status === 'running') {
    const node = graph.nodes[state.graph_node];
    if (!node) {
      state.status = 'failed';
      state.termination_reason = 'failed';
      writeState(state, repoRoot);
      setActive(null, repoRoot);
      return { exitCode: EXIT.FAILED, state, message: `node "${state.graph_node}" not found in graph` };
    }

    // Terminal node
    if (node.terminal) {
      state.status = node.escalates ? 'failed' : 'completed';
      state.termination_reason = node.escalates ? 'needs_human' : 'success';
      state.completed_at = new Date().toISOString();
      writeState(state, repoRoot);
      setActive(null, repoRoot);
      return {
        exitCode: node.escalates ? EXIT.FAILED : EXIT.OK,
        state,
        message: node.escalates
          ? `escalated to terminal — ${state.escalation.question ?? 'no question set'}`
          : `completed successfully — $${state.cost_usd.toFixed(2)} spent`,
      };
    }

    // Transition guard
    if (state.transitions >= MAX_TRANSITIONS) {
      state.status = 'failed';
      state.termination_reason = 'max_transitions';
      state.completed_at = new Date().toISOString();
      writeState(state, repoRoot);
      setActive(null, repoRoot);
      return { exitCode: EXIT.FAILED, state, message: `max transitions (${MAX_TRANSITIONS}) reached` };
    }

    // Budget check
    const budget = checkBudget(state, node);
    if (!budget.allowed) {
      state.status = 'budget_exceeded';
      state.termination_reason = 'budget_exhausted';
      state.completed_at = new Date().toISOString();
      writeState(state, repoRoot);
      setActive(null, repoRoot);
      return { exitCode: EXIT.BUDGET_EXCEEDED, state, message: budget.reason! };
    }

    // Budget slope check (predictive)
    if (budgetSlopeExceeds(state, node)) {
      // Don't halt — just warn. The CLI cap handles the hard stop.
      process.stderr.write(`turbo-flow: warn: budget slope suggests overshoot — tightening node budget\n`);
    }

    // Max iterations check for this node
    const maxIter = node.max_iterations ?? 3;
    if (state.node_iteration >= maxIter) {
      // Exceeded node retries — escalate or fail
      const maxCycles = state.max_cycles;
      if (maxCycles > 0 && state.cycles_used >= maxCycles) {
        state.status = 'failed';
        state.termination_reason = 'max_cycles';
        state.completed_at = new Date().toISOString();
        writeState(state, repoRoot);
        setActive(null, repoRoot);
        return { exitCode: EXIT.FAILED, state, message: `max cycles (${maxCycles}) reached on node "${state.graph_node}"` };
      }

      // Escalate
      const escResult = await escalate(state,
        `Node "${state.graph_node}" failed ${maxIter} iterations without passing gates. Options: (1) continue with current output, (2) abort the run, (3) adjust the spec and retry.`,
        { repoRoot, mention: graph.escalation?.mention, channel: graph.escalation?.channel },
      );
      return { exitCode: EXIT.AWAITING_HUMAN, state, message: `escalated: ${state.escalation.question}` };
    }

    // ── Execute the node ─────────────────────────────────────
    const nodeResult = await executeNode(node, state, host, {
      repoRoot,
      specId,
      graph,
      humanAnswer: state._human_answer,
    });

    // Clean up transient human answer
    state._human_answer = undefined;

    // Update state with node result
    state.cost_usd += nodeResult.cost_usd;
    state.iteration++;
    state.node_iteration++;

    // Record in history
    const iteration = {
      iteration: state.node_iteration,
      session_id: nodeResult.session_id,
      model: nodeResult.model,
      cost_usd: nodeResult.cost_usd,
      turns: nodeResult.turns,
      gates: nodeResult.gateResults,
      passed: nodeResult.gatesPassed ?? false,
      halted_reason: nodeResult.haltedReason ?? null,
      graph_node: state.graph_node,
    };
    state.history.push(iteration);

    writeState(state, repoRoot);

    // If the node execution itself errored
    if (nodeResult.error) {
      // Don't retry on adapter errors — escalate
      const escResult = await escalate(state,
        `Node "${state.graph_node}" encountered an error: ${nodeResult.error}. Options: (1) retry, (2) skip this node, (3) abort the run.`,
        { repoRoot, mention: graph.escalation?.mention, channel: graph.escalation?.channel },
      );
      return { exitCode: EXIT.AWAITING_HUMAN, state, message: `node error escalated: ${nodeResult.error}` };
    }

    // ── Run gates ────────────────────────────────────────────
    if (nodeResult.gatesPassed === null) {
      // Gates not run (no gates defined) — advance
      advanceNode(state, node, true);
      writeState(state, repoRoot);
    } else if (nodeResult.gatesPassed) {
      // Gates passed — advance
      advanceNode(state, node, true);
      writeState(state, repoRoot);
    } else if (nodeResult.needsHuman) {
      // Gate returned needs_human — escalate the question
      const escResult = await escalate(state,
        nodeResult.humanQuestion ?? 'A decision is needed.',
        { repoRoot, mention: graph.escalation?.mention, channel: graph.escalation?.channel },
      );
      return { exitCode: EXIT.AWAITING_HUMAN, state, message: `gate escalated: ${state.escalation.question}` };
    } else {
      // Gates failed — loop back on same node (or escalate if out of retries)
      if (state.node_iteration >= (node.max_iterations ?? 3)) {
        const escResult = await escalate(state,
          `Node "${state.graph_node}" failed gates after ${state.node_iteration} iterations.\n\n${nodeResult.gateFeedback}`,
          { repoRoot, mention: graph.escalation?.mention, channel: graph.escalation?.channel },
        );
        return { exitCode: EXIT.AWAITING_HUMAN, state, message: `max iterations reached, escalated` };
      }
      // Will retry on next loop iteration with feedback in context
      state._gate_feedback = nodeResult.gateFeedback;
    }

    // Single step mode — exit after one node iteration
    if (opts.singleStep) {
      return { exitCode: EXIT.OK, state, message: `stepped: ${state.graph_node} iteration ${state.node_iteration}` };
    }
  }

  return { exitCode: EXIT.OK, state, message: 'run complete' };
}

// ── Internal helpers ────────────────────────────────────────────────

interface NodeResult {
  cost_usd: number;
  session_id: string | null;
  model: string;
  turns: number;
  gateResults: import('../schemas/state.js').GateResult[];
  gatesPassed: boolean | null;
  gateFeedback: string;
  needsHuman: boolean;
  humanQuestion: string | null;
  error?: string;
  haltedReason?: string;
}

async function executeNode(
  node: GraphNode,
  state: RunState,
  host: HostAdapter,
  opts: { repoRoot: string; specId: string; graph: Graph; humanAnswer?: string },
): Promise<NodeResult> {
  const promptPath = join(opts.repoRoot, node.prompt ?? 'prompts/implement.md');
  let prompt: string;

  try {
    prompt = readFileSync(promptPath, 'utf-8');
  } catch {
    return {
      cost_usd: 0, session_id: null, model: state.model, turns: 0,
      gateResults: [], gatesPassed: null, gateFeedback: '',
      needsHuman: false, humanQuestion: null,
      error: `prompt file not found: ${promptPath}`,
    };
  }

  // Substitute stable variables in the cached portion (above CACHE BOUNDARY)
  prompt = prompt
    .replace(/\$\{SPEC_ID\}/g, opts.specId)
    .replace(/\$\{BRANCH\}/g, state.branch)
    .replace(/\$\{GRAPH_NODE\}/g, state.graph_node);

  // Variable content goes BELOW the cache boundary so the cached prefix
  // stays byte-identical across executions of the same node.
  const BOUNDARY = '\n# CACHE BOUNDARY\n';
  const boundaryIdx = prompt.indexOf(BOUNDARY);
  const stablePrefix = boundaryIdx >= 0 ? prompt.slice(0, boundaryIdx + BOUNDARY.length) : prompt;

  // Build the variable tail
  const specContent = readFileSync(join(opts.repoRoot, 'specs', `${opts.specId}.md`), 'utf-8');
  const tail: string[] = [];
  tail.push(`\n## Spec (${opts.specId})\n\n${specContent}`);

  if (opts.humanAnswer) {
    tail.push(`\n## Human decision (from escalation)\n\n${opts.humanAnswer}`);
  }

  const gateFeedback = state._gate_feedback;
  if (gateFeedback) {
    tail.push(`\n## Gate feedback (from previous iteration)\n\n${gateFeedback}`);
    state._gate_feedback = undefined;
  }

  // If the prompt had a cache boundary, insert tail after it;
  // otherwise append to end (backward compat with custom prompts).
  if (boundaryIdx >= 0) {
    const afterBoundary = prompt.slice(boundaryIdx + BOUNDARY.length).trim();
    // Keep any comments that were between the marker and end of file
    const extra = afterBoundary ? `\n${afterBoundary}` : '';
    prompt = stablePrefix + extra + '\n\n' + tail.join('\n\n');
  } else {
    prompt = prompt + '\n\n' + tail.join('\n\n');
  }

  // Budget
  const budget = checkBudget(state, node);

  // Execute via host
  const result = await host.execute({
    prompt,
    model: node.model ?? state.model,
    maxBudgetUsd: budget.hostBudgetCap,
    maxTurns: node.max_turns,
    permissionMode: node.permission_mode,
    allowedTools: node.allowed_tools,
    cwd: opts.repoRoot,
  });

  if (result.error) {
    return {
      cost_usd: result.cost_usd, session_id: result.session_id,
      model: node.model ?? state.model, turns: result.turns,
      gateResults: [], gatesPassed: null, gateFeedback: '',
      needsHuman: false, humanQuestion: null,
      error: result.error,
    };
  }

  // Run gates if defined
  let gateResult: GateRunResult;
  if (node.gates && node.gates.length > 0) {
    gateResult = await runGates(node, result.result_text, host, {
      specId: opts.specId,
      repoRoot: opts.repoRoot,
      model: node.model ?? state.model,
      maxBudgetUsd: budget.hostBudgetCap - result.cost_usd,
    });
  } else {
    gateResult = { passed: true, results: [], feedback: '', needsHuman: false, question: null };
  }

  // Add gate cost to total
  const gateCost = gateResult.results.reduce((s, r) => {
    // Gate costs come from judge gates — approximated from judge calls
    return s;
  }, 0);

  return {
    cost_usd: result.cost_usd + gateCost,
    session_id: result.session_id,
    model: node.model ?? state.model,
    turns: result.turns,
    gateResults: gateResult.results,
    gatesPassed: gateResult.passed,
    gateFeedback: gateResult.feedback,
    needsHuman: gateResult.needsHuman,
    humanQuestion: gateResult.question,
  };
}

/** Advance to the next node based on gate result */
function advanceNode(state: RunState, node: GraphNode, passed: boolean): void {
  const nextNode = passed ? node.on_pass : node.on_fail;

  if (!nextNode) {
    state.status = 'failed';
    state.termination_reason = 'failed';
    state.completed_at = new Date().toISOString();
    return;
  }

  // Track cycle usage
  if (nextNode === state.graph_node) {
    // Self-loop (unusual but possible)
    return;
  }

  // If we're going backward (fail edge), count it as a cycle
  if (!passed && nextNode !== node.on_pass) {
    // Check if this forms a known cycle
    // Simple heuristic: if the next node has been visited, it's a cycle
    const visited = new Set(state.history.map(h => h.graph_node));
    if (visited.has(nextNode)) {
      state.cycles_used++;
    }
  }

  // Reset node iteration when moving to a new node
  if (nextNode !== state.graph_node) {
    state.node_iteration = 0;
    state.transitions++;
    state.graph_node = nextNode;
  }
}
