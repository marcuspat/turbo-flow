import { NextResponse } from 'next/server';
import { execSync } from 'child_process';
import { VAULT_PATH, INTAKE_PATH, TB_ROOT } from '@/lib/vault';

export async function GET() {
  try {
    const waveRunner = `${TB_ROOT}/lib/wave_runner.py`;

    // Run all waves in dry-run mode
    const results: Record<string, unknown> = {};
    for (const wave of ['triage', 'distill', 'sweep'] as const) {
      try {
        const args = wave === 'sweep'
          ? `"${waveRunner}" --vault "${VAULT_PATH}" --wave ${wave} --dry-run`
          : `"${waveRunner}" --vault "${VAULT_PATH}" --intake "${INTAKE_PATH}" --wave ${wave} --dry-run`;
        const output = execSync(`python3 ${args}`, { encoding: 'utf-8', timeout: 15000 });
        results[wave] = JSON.parse(output);
      } catch {
        results[wave] = { error: 'wave runner failed', wave };
      }
    }

    // Wave heartbeat
    const wavesFile = `${VAULT_PATH}/.turbo-brain-waves`;
    const waveStatus: Record<string, { lastSuccess: string | null; status: string }> = {};
    const budgets = { triage: 36, distill: 252, sweep: 1080 };
    const now = Date.now() / 1000;

    for (const [name, maxH] of Object.entries(budgets)) {
      let ts: number | null = null;
      if (fs.existsSync(wavesFile)) {
        const content = fs.readFileSync(wavesFile, 'utf-8');
        for (const line of content.split('\n')) {
          const parts = line.trim().split(' ');
          if (parts[0] === name && parts[1]) {
            ts = parseFloat(parts[1]);
          }
        }
      }
      if (ts === null) {
        waveStatus[name] = { lastSuccess: null, status: 'NOT YET RUN' };
      } else {
        const age = (now - ts) / 3600;
        waveStatus[name] = {
          lastSuccess: new Date(ts * 1000).toISOString(),
          status: age > maxH ? 'STALE' : 'ok',
        };
      }
    }

    return NextResponse.json({ results, waveStatus });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}

import fs from 'fs';