// ─── Claude Code host adapter ───────────────────────────────────────
// Calls `claude -p` with structured output. The only host in v5 MVP.
//
// Requires Claude Code CLI installed (`npm install -g @anthropic-ai/claude-code`)
// and either CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY in the environment.

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import type { HostAdapter, HostExecuteResult } from './adapter.js';

const execFileAsync = promisify(execFile);

interface ClaudeJsonOutput {
  result?: string;
  total_cost_usd?: number;
  session_id?: string;
  num_turns?: number;
  is_error?: boolean;
}

export class ClaudeAdapter implements HostAdapter {
  readonly name = 'claude';
  readonly supportsCLIBudgetCap = true;

  async execute(opts: {
    prompt: string;
    model: string;
    maxBudgetUsd: number;
    maxTurns?: number;
    permissionMode?: string;
    allowedTools?: string;
    jsonSchema?: object;
    resumeSession?: string;
    cwd: string;
  }): Promise<HostExecuteResult> {
    const args: string[] = [
      '-p', opts.prompt,
      '--output-format', 'json',
      '--model', opts.model,
      '--max-budget-usd', String(opts.maxBudgetUsd),
    ];

    if (opts.maxTurns) {
      args.push('--max-turns', String(opts.maxTurns));
    }

    if (opts.permissionMode) {
      args.push('--permission-mode', opts.permissionMode);
    }

    if (opts.allowedTools) {
      args.push('--allowedTools', opts.allowedTools);
    }

    if (opts.jsonSchema) {
      // Write schema to a temp file and reference it
      const { writeFileSync, mkdtempSync } = await import('node:fs');
      const { tmpdir } = await import('node:os');
      const { join } = await import('node:path');
      const tmpDir = mkdtempSync(join(tmpdir(), 'tf-verdict-'));
      const schemaPath = join(tmpDir, 'verdict.json');
      writeFileSync(schemaPath, JSON.stringify(opts.jsonSchema));
      args.push('--json-schema', schemaPath);
    }

    if (opts.resumeSession) {
      args.push('--resume', opts.resumeSession);
    }

    return this.runClaude(args, opts.cwd);
  }

  async judge(opts: {
    rubric: string;
    content: string;
    model: string;
    maxBudgetUsd: number;
    cwd: string;
  }): Promise<HostExecuteResult> {
    const prompt = `You are a gate judge. Evaluate the following content against this rubric.

Return ONLY a JSON object with this exact shape (no markdown, no backticks):
{"pass": boolean, "blocking": string[], "non_blocking": string[], "not_verified": string[], "needs_human": boolean, "question": string|null, "evidence": string[]}

## Rubric
${opts.rubric}

## Content to evaluate
${opts.content}`;

    return this.execute({
      prompt,
      model: opts.model,
      maxBudgetUsd: opts.maxBudgetUsd,
      maxTurns: 5,
      cwd: opts.cwd,
      jsonSchema: {
        type: 'object',
        additionalProperties: false,
        properties: {
          pass: { type: 'boolean' },
          blocking: { type: 'array', items: { type: 'string' } },
          non_blocking: { type: 'array', items: { type: 'string' } },
          not_verified: { type: 'array', items: { type: 'string' } },
          needs_human: { type: 'boolean' },
          question: { type: 'string' },
          evidence: { type: 'array', items: { type: 'string' } },
        },
        required: ['pass', 'blocking', 'needs_human', 'evidence'],
      },
    });
  }

  private async runClaude(args: string[], cwd: string): Promise<HostExecuteResult> {
    try {
      const { stdout, stderr } = await execFileAsync('claude', args, {
        cwd,
        timeout: 90 * 60 * 1000, // 90 min hard timeout
        maxBuffer: 10 * 1024 * 1024, // 10MB
        env: { ...process.env },
      });

      // Parse JSON from stdout — Claude may prepend/append non-JSON
      const jsonMatch = stdout.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        return {
          result_text: stdout,
          cost_usd: 0,
          session_id: null,
          turns: 0,
          error: `Claude output was not valid JSON: ${stdout.slice(0, 500)}`,
        };
      }

      const parsed: ClaudeJsonOutput = JSON.parse(jsonMatch[0]);

      if (parsed.is_error) {
        return {
          result_text: parsed.result ?? '',
          cost_usd: parsed.total_cost_usd ?? 0,
          session_id: parsed.session_id ?? null,
          turns: parsed.num_turns ?? 0,
          error: parsed.result ?? 'Claude returned is_error=true',
        };
      }

      return {
        result_text: parsed.result ?? '',
        cost_usd: parsed.total_cost_usd ?? 0,
        session_id: parsed.session_id ?? null,
        turns: parsed.num_turns ?? 0,
      };
    } catch (err: unknown) {
      const e = err as { code?: string; message?: string; stderr?: string };
      if (e.code === 'ENOENT') {
        return {
          result_text: '',
          cost_usd: 0,
          session_id: null,
          turns: 0,
          error: 'claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code',
        };
      }
      return {
        result_text: '',
        cost_usd: 0,
        session_id: null,
        turns: 0,
        error: `claude CLI failed: ${e.message ?? String(e)}`,
      };
    }
  }
}

/** Create the adapter (factory for future host switching) */
export function createHostAdapter(hostName: string = 'claude'): HostAdapter {
  switch (hostName) {
    case 'claude':
      return new ClaudeAdapter();
    default:
      throw new Error(`Unknown host: ${hostName}. Supported: claude`);
  }
}
