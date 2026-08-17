// ─── Verdict schema ───────────────────────────────────────────────────
// The shape every judge verdict must take. Enforced by JSON Schema validation
// on the host's --json-schema flag, AND re-validated by the engine after parse.

export interface Verdict {
  pass: boolean;
  blocking: string[];
  non_blocking?: string[];
  not_verified?: string[];
  needs_human: boolean;
  question?: string;
  evidence: string[];
}

/** JSON Schema for verdict — passed to --json-schema / --output-schema */
export const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    pass: {
      type: 'boolean',
      description: 'true only if every blocking criterion in the rubric is satisfied with evidence. Absence of evidence is not pass.',
    },
    blocking: {
      type: 'array',
      items: { type: 'string' },
      description: 'Things that must be fixed before this node can advance. Each entry must be specific enough to act on without asking a follow-up question: name the file, the symbol, the command, the observed vs expected behaviour.',
    },
    non_blocking: {
      type: 'array',
      items: { type: 'string' },
      description: 'Real issues that do not justify another loop iteration.',
    },
    not_verified: {
      type: 'array',
      items: { type: 'string' },
      description: 'Criteria you could not check, and why. Never imply coverage you do not have.',
    },
    needs_human: {
      type: 'boolean',
      description: 'true when the blocker is a DECISION rather than a DEFECT — a product/scope/tradeoff/credentials call the agent must not make unilaterally.',
    },
    question: {
      type: 'string',
      description: 'When needs_human is true: one sentence, phrased as a concrete choice with the options named.',
    },
    evidence: {
      type: 'array',
      items: { type: 'string' },
      description: 'What you actually inspected — file paths, commands run, diffs read. Required on pass as well as fail.',
    },
  },
  required: ['pass', 'blocking', 'needs_human', 'evidence'],
} as const;

/** Validate a verdict object against the schema */
export function validateVerdict(v: unknown): { valid: boolean; errors: string[] } {
  const errors: string[] = [];
  if (typeof v !== 'object' || v === null) return { valid: false, errors: ['verdict is not an object'] };
  const obj = v as Record<string, unknown>;

  if (typeof obj.pass !== 'boolean') errors.push('pass must be boolean');
  if (!Array.isArray(obj.blocking)) errors.push('blocking must be an array');
  if (typeof obj.needs_human !== 'boolean') errors.push('needs_human must be boolean');
  if (!Array.isArray(obj.evidence)) errors.push('evidence must be an array');

  if (obj.needs_human === true && !obj.question) {
    errors.push('question is required when needs_human is true');
  }
  if (obj.needs_human === true && typeof obj.question !== 'string') {
    errors.push('question must be a string');
  }

  return { valid: errors.length === 0, errors };
}
