// ─── turbo-flow new ───────────────────────────────
// Scaffold a new spec from the template.
import { existsSync, readdirSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
export async function newCommand(slug) {
    const repoRoot = process.cwd();
    const specsDir = join(repoRoot, 'specs');
    if (!existsSync(specsDir)) {
        mkdirSync(specsDir, { recursive: true });
    }
    // Find the next spec number
    const existing = readdirSync(specsDir)
        .filter(f => f.endsWith('.md') && f !== 'TEMPLATE.md')
        .map(f => parseInt(f.split('-')[0], 10))
        .filter(n => !isNaN(n));
    const nextNum = existing.length > 0 ? Math.max(...existing) + 1 : 1;
    const specId = `${String(nextNum).padStart(3, '0')}-${slug}`;
    const specPath = join(specsDir, `${specId}.md`);
    // Read template
    const templatePath = join(specsDir, 'TEMPLATE.md');
    if (!existsSync(templatePath)) {
        // Use built-in template
        const builtIn = join(repoRoot, 'node_modules/turbo-flow/templates/specs/TEMPLATE.md');
        if (!existsSync(builtIn)) {
            console.error('turbo-flow: spec TEMPLATE.md not found. Run turbo-flow init first.');
            process.exit(1);
        }
    }
    const template = readFileSync(existsSync(templatePath) ? templatePath : join(repoRoot, 'node_modules/turbo-flow/templates/specs/TEMPLATE.md'), 'utf-8');
    const date = new Date().toISOString().split('T')[0];
    const content = template
        .replace(/__ID__/g, specId)
        .replace(/__DATE__/g, date);
    writeFileSync(specPath, content, 'utf-8');
    console.log(`turbo-flow: created specs/${specId}.md`);
    console.log(`turbo-flow: fill it in with /spec or your editor, then run:`);
    console.log(`  turbo-flow run ${specId}`);
}
//# sourceMappingURL=new.js.map