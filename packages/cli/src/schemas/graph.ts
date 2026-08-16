// ─── Graph schema types ─────────────────────────────────────────────────
// One file is the whole control surface: change what the harness does by
// editing graph.json, not by editing the engine.

import { readFileSync } from 'node:fs';

/** Which host runs a node. Extend for codex, etc. */
export type HostName = 'claude';

/** Gate types */
export type GateType = 'cmd' | 'judge';

/** A single gate on a node */
export interface Gate {
  id: string;
  type: GateType;
  run?: string;
  rubric?: string;
  model?: string;
  optional_if_absent?: boolean;
  _why?: string;
}

/** A node in the graph */
export interface GraphNode {
  _purpose?: string;
  prompt?: string;
  model?: string;
  max_iterations?: number;
  budget_usd?: number;
  max_turns?: number;
  permission_mode?: string;
  allowed_tools?: string;
  writes?: string[];
  gates?: Gate[];
  on_pass?: string;
  on_fail?: string;
  terminal?: boolean;
  escalates?: boolean;
  agent?: string;
  host?: HostName;
  _note?: string;
  [key: string]: unknown;
}

/** Escalation configuration */
export interface EscalationConfig {
  channel: 'github_issue' | 'notification';
  mention?: string;
}

/** The graph definition */
export interface Graph {
  version: number;
  name: string;
  budget_usd?: number;
  default_model?: string;
  escalation?: EscalationConfig;
  entry: string;
  nodes: Record<string, GraphNode>;
}

/** Parse and validate graph.json */
export function loadGraph(filePath: string): Graph {
  const raw = readFileSync(filePath, 'utf-8');
  return JSON.parse(raw) as Graph;
}

/** Validate graph structure — all edges land on real nodes */
export function validateGraph(graph: Graph): string[] {
  const errors: string[] = [];
  const nodeKeys = Object.keys(graph.nodes);

  if (!nodeKeys.includes(graph.entry)) {
    errors.push(`entry "${graph.entry}" is not a defined node`);
  }

  for (const [key, node] of Object.entries(graph.nodes)) {
    if (node.terminal) continue;
    const checkEdge = (edge: string | undefined, label: string) => {
      if (!edge) return;
      if (!nodeKeys.includes(edge)) {
        errors.push(`node "${key}" ${label} "${edge}" is not a defined node`);
      }
    };
    checkEdge(node.on_pass, 'on_pass');
    checkEdge(node.on_fail, 'on_fail');
  }

  return errors;
}

/** Find cycle pairs for max_cycles enforcement */
export function findCycles(graph: Graph): [string, string][] {
  const cycles: [string, string][] = [];
  for (const [key, node] of Object.entries(graph.nodes)) {
    if (node.on_fail && node.on_fail !== key) {
      const target = graph.nodes[node.on_fail];
      if (target?.on_pass === key) {
        cycles.push([key, node.on_fail]);
      }
    }
  }
  return cycles;
}
