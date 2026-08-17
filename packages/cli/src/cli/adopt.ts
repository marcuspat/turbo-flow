// ─── turbo-flow adopt ───────────────────────────────────────
// Compile the contract source into CLAUDE.md (and optionally AGENTS.md).
// The contract is the single source of truth for how agents in this
// repo should behave. It is compiled, not hand-edited.

import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';

/** Inline variable references: {{graph.entry}}, {{graph.budget_usd}}, etc. */
function expandVars(tmpl: string, graph: Record<string, unknown>): string {
  return tmpl.replace(/\{\{([^}]+)\}\}/g, (_, path) => {
    const parts = path.trim().split('.');
    let val: unknown = graph;
    for (const p of parts) {
      if (val && typeof val === 'object') val = (val as Record<string, unknown>)[p];
      else return `{{${path}}}`;
    }
    return val === undefined ? `{{${path}}}` : String(val);
  });
}

/** Read the gate commands from graph.json for the contract */
function extractGateSummary(graph: Record<string, unknown>): string {
  const nodes = graph.nodes as Record<string, Record<string, unknown>> | undefined;
  if (!nodes) return '';

  const lines: string[] = ['### Gate wiring\n'];
  for (const [name, node] of Object.entries(nodes)) {
    const gates = node.gates as Array<{ id: string; type: string; run?: string; rubric?: string }> | undefined;
    if (!gates || gates.length === 0) continue;
    const gateStr = gates.map(g => {
      if (g.type === 'cmd') return `\`${g.run}\` (deterministic)`;
      return `\`${g.rubric ?? g.id}\` (judge)`;
    }).join(', ');
    lines.push(`- **${name}**: ${gateStr}`);
  }
  return lines.join('\n') + '\n';
}

export async function adoptCommand(opts: { output?: string }) {
  const repoRoot = process.cwd();
  const sourcePath = join(repoRoot, 'contract', 'source.md');
  const graphPath = join(repoRoot, 'graph.json');

  if (!existsSync(sourcePath)) {
    console.error('turbo-flow: contract/source.md not found. Run turbo-flow init first.');
    process.exit(1);
  }

  let graph: Record<string, unknown> = {};
  if (existsSync(graphPath)) {
    try {
      graph = JSON.parse(readFileSync(graphPath, 'utf-8'));
    } catch {
      console.error('turbo-flow: graph.json is not valid JSON');
      process.exit(1);
    }
  }

  let source = readFileSync(sourcePath, 'utf-8');

  // Expand variables
  source = expandVars(source, graph);

  // Append gate wiring section
  const gateSummary = extractGateSummary(graph);
  if (gateSummary) {
    source += '\n---\n\n' + gateSummary;
  }

  // Write to CLAUDE.md (default) or custom path
  const outPath = opts.output
    ? (opts.output.startsWith('/') ? opts.output : join(repoRoot, opts.output))
    : join(repoRoot, 'CLAUDE.md');

  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, source, 'utf-8');
  console.log(`turbo-flow: contract compiled → ${outPath.replace(repoRoot + '/', '')}`);
  console.log(`  ${source.split('\n').length} lines, ${source.length} bytes`);
}
