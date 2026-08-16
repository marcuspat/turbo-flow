// ─── turbo-flow doctor ────────────────────────────────
// Check dependencies and repo wiring. Must print all ✓ before
// you go further.

import { existsSync, readFileSync, accessSync, constants } from 'node:fs';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

export async function doctorCommand() {
  const repoRoot = process.cwd();
  let allOk = true;

  const check = (label: string, ok: boolean, detail?: string) => {
    const icon = ok ? '✓' : '✗';
    const msg = detail ? ` ${detail}` : '';
    console.log(`  ${icon} ${label}${msg}`);
    if (!ok) allOk = false;
  };

  console.log('turbo-flow doctor');
  console.log('');

  // Dependencies
  check('git', tryExec('git', ['--version']));
  check('node >= 18', checkNodeVersion());
  check('jq', tryExec('jq', ['--version']));
  check('claude', tryExec('claude', ['--version']));

  // Optional
  const hasGh = tryExec('gh', ['auth', 'status']);
  if (hasGh) {
    check('gh (GitHub CLI)', true);
  } else {
    console.log('  ○ gh — not found (needed for Lane B escalation)');
  }

  console.log('');

  // Repo wiring
  check('graph.json', existsSync(join(repoRoot, 'graph.json')),
    existsSync(join(repoRoot, 'graph.json')) ? 'found' : 'missing — run turbo-flow init');

  check('specs/', existsSync(join(repoRoot, 'specs')),
    existsSync(join(repoRoot, 'specs')) ? 'found' : 'missing');

  check('prompts/', existsSync(join(repoRoot, 'prompts')),
    existsSync(join(repoRoot, 'prompts')) ? 'found' : 'missing');

  check('gates/', existsSync(join(repoRoot, 'gates')),
    existsSync(join(repoRoot, 'gates')) ? 'found' : 'missing');

  // Validate graph.json edges
  if (existsSync(join(repoRoot, 'graph.json'))) {
    try {
      const { loadGraph, validateGraph } = await import('../schemas/graph.js');
      const graph = loadGraph(join(repoRoot, 'graph.json'));
      const errors = validateGraph(graph);
      check('graph edges', errors.length === 0,
        errors.length === 0 ? 'valid' : errors.join('; '));
    } catch (e: any) {
      check('graph.json parse', false, e.message);
    }
  }

  // Claude Code hooks
  const settingsPath = join(repoRoot, '.claude', 'settings.json');
  if (existsSync(settingsPath)) {
    const settings = JSON.parse(readFileSync(settingsPath, 'utf-8'));
    const hooks = (settings as any).hooks;
    check('.claude/hooks (Stop)', !!(hooks?.Stop), hooks?.Stop ? 'wired' : 'missing');
    check('.claude/hooks (PreToolUse)', !!(hooks?.PreToolUse), hooks?.PreToolUse ? 'wired' : 'missing');
    check('.claude/hooks (Notification)', !!(hooks?.Notification), hooks?.Notification ? 'wired' : 'missing');
    check('.claude/hooks (SessionStart)', !!(hooks?.SessionStart), hooks?.SessionStart ? 'wired' : 'missing');
  } else {
    check('.claude/settings.json', false, 'missing — run turbo-flow init');
  }

  console.log('');
  if (allOk) {
    console.log('  All checks passed. Ready to run specs.');
  } else {
    console.log('  Some checks failed. Fix the above before running specs.');
  }
}

function tryExec(cmd: string, args: string[]): boolean {
  try {
    execFileSync(cmd, args, { stdio: 'pipe', timeout: 10_000 });
    return true;
  } catch {
    return false;
  }
}

function checkNodeVersion(): boolean {
  const major = parseInt(process.versions.node.split('.')[0], 10);
  return major >= 18;
}
