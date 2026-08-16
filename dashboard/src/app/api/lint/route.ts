import { NextResponse } from 'next/server';
import { execSync } from 'child_process';
import { VAULT_PATH, TB_ROOT } from '@/lib/vault';

export async function GET() {
  try {
    const result = execSync(
      `python3 "${TB_ROOT}/lib/lint.py" --json "${VAULT_PATH}"`,
      { encoding: 'utf-8', timeout: 10000 },
    );
    return NextResponse.json(JSON.parse(result));
  } catch (error: unknown) {
    const errMsg = error instanceof Error ? error.message : String(error);
    // lint returns non-zero on errors — try to parse stdout anyway
    const stdout = (error as { stdout?: string })?.stdout;
    if (stdout) {
      try {
        return NextResponse.json(JSON.parse(stdout));
      } catch {
        // fall through
      }
    }
    return NextResponse.json({ error: errMsg }, { status: 500 });
  }
}
