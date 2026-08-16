/**
 * Turbo Brain vault utilities — shared between API routes.
 * Reads the demo vault directly from the filesystem.
 */

import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';

export const VAULT_PATH = path.join(process.cwd(), 'demo-vault');
export const INTAKE_PATH = path.join(process.cwd(), 'demo-intake');
export const TB_ROOT = path.join(process.cwd(), 'turbo-brain');

export const CURATED_DIRS = ['profile', 'areas', 'people', 'projects', 'topics', 'daily'] as const;
export type CuratedDir = (typeof CURATED_DIRS)[number];

export interface VaultFile {
  name: string;
  path: string;
  category: CuratedDir;
  description: string;
  sensitivity: 'private' | 'shareable' | 'public';
  factCount: number;
  sources: string[];
}

export interface Fact {
  tag: 'stated' | 'ingested' | 'derived';
  fact: string;
  line: number;
}

export interface ParsedFile {
  frontmatter: {
    name: string;
    description: string;
    sources: string[];
    sensitivity: string;
    aliases?: string[];
  };
  facts: Fact[];
  relatedLinks: string[];
  raw: string;
}

const FACT_RE = /^- \[(stated|ingested|derived)\]\s+(.+)$/;
const WIKILINK_RE = /\[\[([^\]]+)\]\]/g;

function parseFrontmatter(text: string): { fm: Record<string, unknown>; body: string } {
  const lines = text.split('\n');
  if (lines[0]?.trim() !== '---') return { fm: {}, body: text };
  const end = lines.findIndex((l, i) => i > 0 && l.trim() === '---');
  if (end === -1) return { fm: {}, body: text };
  const fm: Record<string, unknown> = {};
  for (const raw of lines.slice(1, end)) {
    const idx = raw.indexOf(':');
    if (idx === -1) continue;
    const k = raw.slice(0, idx).trim();
    let v = raw.slice(idx + 1).trim();
    if (v.startsWith('[') && v.endsWith(']')) {
      v = v.slice(1, -1).split(',').map(s => s.trim()).filter(Boolean);
    }
    fm[k] = v;
  }
  return { fm, body: lines.slice(end + 1).join('\n') };
}

export function parseVaultFile(content: string): ParsedFile {
  const { fm, body } = parseFrontmatter(content);
  const facts: Fact[] = [];
  const relatedLinks: string[] = [];
  const bodyLines = body.split('\n');

  for (let i = 0; i < bodyLines.length; i++) {
    const line = bodyLines[i];
    if (line.startsWith('- Related:')) {
      let match: RegExpExecArray | null;
      const rx = /\[\[([^\]]+)\]\]/g;
      while ((match = rx.exec(line)) !== null) {
        relatedLinks.push(match[1]);
      }
      continue;
    }
    const m = FACT_RE.exec(line);
    if (m) {
      facts.push({ tag: m[1] as Fact['tag'], fact: m[2], line: i + 1 });
    }
  }

  return {
    frontmatter: {
      name: (fm.name as string) || '',
      description: (fm.description as string) || '',
      sources: (fm.sources as string[]) || [],
      sensitivity: (fm.sensitivity as string) || 'private',
      aliases: fm.aliases as string[] | undefined,
    },
    facts,
    relatedLinks,
    raw: content,
  };
}

export function listVaultFiles(): VaultFile[] {
  const files: VaultFile[] = [];
  for (const dir of CURATED_DIRS) {
    const dirPath = path.join(VAULT_PATH, dir);
    if (!fs.existsSync(dirPath)) continue;
    const entries = fs.readdirSync(dirPath, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isFile() || !entry.name.endsWith('.md')) continue;
      const fullPath = path.join(dirPath, entry.name);
      const content = fs.readFileSync(fullPath, 'utf-8');
      const parsed = parseVaultFile(content);
      files.push({
        name: parsed.frontmatter.name || entry.name.replace('.md', ''),
        path: `${dir}/${entry.name}`,
        category: dir,
        description: parsed.frontmatter.description,
        sensitivity: parsed.frontmatter.sensitivity as VaultFile['sensitivity'],
        factCount: parsed.facts.length,
        sources: parsed.frontmatter.sources,
      });
    }
  }
  return files;
}

export function readVaultFile(name: string): ParsedFile | null {
  const safeName = path.basename(name);
  if (safeName !== name || safeName.includes('..')) return null;
  for (const dir of CURATED_DIRS) {
    const p = path.join(VAULT_PATH, dir, safeName.endsWith('.md') ? safeName : `${safeName}.md`);
    if (fs.existsSync(p)) {
      return parseVaultFile(fs.readFileSync(p, 'utf-8'));
    }
  }
  return null;
}

export function searchVault(query: string): { file: string; line: number; text: string; category: string }[] {
  const files = listVaultFiles();
  const hits: { file: string; line: number; text: string; category: string }[] = [];
  const lowerQ = query.toLowerCase();
  const limit = 40;

  for (const vf of files) {
    if (hits.length >= limit) break;
    const fullPath = path.join(VAULT_PATH, vf.path);
    const lines = fs.readFileSync(fullPath, 'utf-8').split('\n');
    for (let i = 0; i < lines.length; i++) {
      if (hits.length >= limit) break;
      if (lines[i].toLowerCase().includes(lowerQ)) {
        hits.push({
          file: vf.path,
          line: i + 1,
          text: lines[i].trim(),
          category: vf.category,
        });
      }
    }
  }
  return hits;
}

export function getDoctorData() {
  const files = listVaultFiles();
  const byCategory: Record<string, number> = {};
  let totalFacts = 0;
  for (const f of files) {
    byCategory[f.category] = (byCategory[f.category] || 0) + 1;
    totalFacts += f.factCount;
  }

  let vaultSize = 0;
  for (const dir of CURATED_DIRS) {
    const dirPath = path.join(VAULT_PATH, dir);
    if (!fs.existsSync(dirPath)) continue;
    for (const entry of fs.readdirSync(dirPath, { withFileTypes: true })) {
      if (entry.isFile() && entry.name.endsWith('.md')) {
        vaultSize += fs.statSync(path.join(dirPath, entry.name)).size;
      }
    }
  }

  // Count intake
  const inboxPath = path.join(INTAKE_PATH, 'inbox');
  let intakeCount = 0;
  if (fs.existsSync(inboxPath)) {
    intakeCount = fs.readdirSync(inboxPath).filter(n => n.endsWith('.md')).length;
  }

  // Deny list
  const denyPath = path.join(VAULT_PATH, 'CLIENTS.deny');
  let denyTerms = 0;
  if (fs.existsSync(denyPath)) {
    denyTerms = fs.readFileSync(denyPath, 'utf-8')
      .split('\n').filter(l => l.trim() && !l.trim().startsWith('#')).length;
  }

  // Run lint
  let lintPassed = false;
  let lintErrors = 0;
  try {
    const result = execSync(`python3 "${TB_ROOT}/lib/lint.py" --json "${VAULT_PATH}"`, {
      encoding: 'utf-8', timeout: 10000,
    });
    const data = JSON.parse(result);
    lintPassed = data.errors.length === 0;
    lintErrors = data.errors.length;
  } catch {
    lintPassed = false;
    lintErrors = -1;
  }

  return {
    toolchain: {
      git: true,
      python3: true,
      rg: true,
    },
    vault: {
      filesByCategory: byCategory,
      totalFiles: files.length,
      totalFacts,
      sizeBytes: vaultSize,
      sizeKB: Math.round(vaultSize / 1024),
      d4Trigger: vaultSize > 3 * 1024 * 1024,
    },
    denyList: {
      present: fs.existsSync(denyPath),
      terms: denyTerms,
      status: denyTerms > 0 ? 'ok' : 'UNARMED',
    },
    intake: {
      undistilled: intakeCount,
    },
    lint: { passed: lintPassed, errors: lintErrors },
    timestamp: new Date().toISOString(),
  };
}
