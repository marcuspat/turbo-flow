import { NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';
import { INTAKE_PATH } from '@/lib/vault';

export async function GET() {
  try {
    const inboxPath = path.join(INTAKE_PATH, 'inbox');
    const files: { name: string; size: number; modified: string; preview: string }[] = [];
    
    if (fs.existsSync(inboxPath)) {
      const entries = fs.readdirSync(inboxPath).filter(n => n.endsWith('.md')).sort();
      for (const name of entries) {
        const fp = path.join(inboxPath, name);
        const stat = fs.statSync(fp);
        const content = fs.readFileSync(fp, 'utf-8');
        files.push({
          name,
          size: stat.size,
          modified: stat.mtime.toISOString(),
          preview: content.slice(0, 120).trim(),
        });
      }
    }
    
    return NextResponse.json({ files, count: files.length });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
