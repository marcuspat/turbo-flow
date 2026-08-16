// ─── turbo-flow init ─────────────────────────────────────────
// Scaffolds the harness into the current repo. One set of files,
// five surfaces.

import { existsSync, mkdirSync, cpSync, writeFileSync, readFileSync, chmodSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const TEMPLATES_DIR = join(dirname(__filename), '..', '..', 'templates');

interface InitOpts {
  devcontainer?: boolean;
  profile?: string;
}

export async function init(opts: InitOpts = {}): Promise<void> {
  const cwd = process.cwd();

  // Check we're in a git repo
  const { execFileSync } = await import('node:child_process');
  try {
    execFileSync('git', ['rev-parse', '--show-toplevel'], { cwd, stdio: 'pipe' });
  } catch {
    console.error('turbo-flow: not in a git repository');
    process.exit(1);
  }

  // Verify templates exist
  if (!existsSync(TEMPLATES_DIR)) {
    console.error(`turbo-flow: templates not found at ${TEMPLATES_DIR}`);
    process.exit(1);
  }

  const files = [
    // Core engine files
    'graph.json',
    'schemas/verdict.schema.json',

    // Spec template
    'specs/TEMPLATE.md',

    // Prompts
    'prompts/plan.md',
    'prompts/implement.md',
    'prompts/verify.md',
    'prompts/ship.md',

    // Gates
    'gates/structural.sh',
    'gates/build.sh',
    'gates/tests.sh',
    'gates/pr-open.sh',
    'gates/rubrics/plan.md',
    'gates/rubrics/verify.md',

    // Claude Code hooks + commands + settings
    '.claude/settings.json',
    '.claude/hooks/stop-gate.sh',
    '.claude/hooks/guard.sh',
    '.claude/hooks/notify.sh',
    '.claude/hooks/context.sh',
    '.claude/commands/spec.md',
    '.claude/commands/wave.md',
    '.claude/commands/adopt.md',

    // GitHub Actions (Lane B)
    '.github/workflows/tf-wave.yml',
    '.github/workflows/tf-answer.yml',

    // Contract source
    'contract/source.md',
  ];

  // Devcontainer (optional)
  if (opts.devcontainer) {
    files.push('.devcontainer/devcontainer.json');
  }

  let created = 0;
  let skipped = 0;

  for (const file of files) {
    const src = join(TEMPLATES_DIR, file);
    const dest = join(cwd, file);

    if (!existsSync(src)) {
      console.error(`turbo-flow: warn: template ${file} not found, skipping`);
      skipped++;
      continue;
    }

    if (existsSync(dest)) {
      // For .claude/settings.json, merge instead of overwriting
      if (file === '.claude/settings.json') {
        mergeSettings(src, dest);
        created++;
        continue;
      }
      console.log(`  exists: ${file} (not overwritten)`);
      skipped++;
      continue;
    }

    mkdirSync(dirname(dest), { recursive: true });
    cpSync(src, dest);
    try { chmodSync(dest, 0o755); } catch { /* ignore */ }
    created++;
    console.log(`  created: ${file}`);
  }

  // Make shell scripts executable
  const shellFiles = files.filter(f => f.endsWith('.sh'));
  for (const file of shellFiles) {
    const dest = join(cwd, file);
    if (existsSync(dest)) {
      try { chmodSync(dest, 0o755); } catch { /* ignore */ }
    }
  }

  // Update .gitignore
  updateGitignore(cwd);

  // Create specs/ directory if it doesn't exist
  const specsDir = join(cwd, 'specs');
  if (!existsSync(specsDir)) {
    mkdirSync(specsDir, { recursive: true });
  }

  console.log(`\nturbo-flow: ${created} files created, ${skipped} skipped`);
  console.log('turbo-flow: run `turbo-flow doctor` to verify setup');
}

function mergeSettings(src: string, dest: string) {
  const existing = JSON.parse(readFileSync(dest, 'utf-8'));
  const incoming = JSON.parse(readFileSync(src, 'utf-8'));

  // Merge hooks arrays
  if (incoming.hooks) {
    existing.hooks = existing.hooks ?? {};
    for (const [event, hooks] of Object.entries(incoming.hooks)) {
      const existingHooks = (existing.hooks as Record<string, unknown[]>)[event] ?? [];
      const incomingHooks = hooks as unknown[];
      // Prepend incoming hooks so they run first
      (existing.hooks as Record<string, unknown[]>)[event] = [
        ...incomingHooks,
        ...existingHooks,
      ];
    }
  }

  writeFileSync(dest, JSON.stringify(existing, null, 2) + '\n', 'utf-8');
  console.log('  merged: .claude/settings.json (hooks appended)');
}

function updateGitignore(cwd: string) {
  const giPath = join(cwd, '.gitignore');
  const entries = [
    '.lg/runs/*/logs/',
    '.lg/active',
    '.lg/runs/*/.stop-guard',
  ];

  let content = '';
  if (existsSync(giPath)) {
    content = readFileSync(giPath, 'utf-8');
  }

  let added = 0;
  for (const entry of entries) {
    if (!content.includes(entry)) {
      content += `\n${entry}`;
      added++;
    }
  }

  if (added > 0) {
    writeFileSync(giPath, content + '\n', 'utf-8');
    console.log(`  updated: .gitignore (${added} entries added)`);
  }
}
