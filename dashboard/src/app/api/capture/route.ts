import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';
import { INTAKE_PATH } from '@/lib/vault';

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const text = body?.text?.trim();
    if (!text) {
      return NextResponse.json({ error: 'text is required' }, { status: 400 });
    }
    if (text.length > 4000) {
      return NextResponse.json({ error: 'capture too long (max 4000 chars)' }, { status: 400 });
    }

    const inboxPath = path.join(INTAKE_PATH, 'inbox');
    fs.mkdirSync(inboxPath, { recursive: true });

    const ts = new Date().toISOString().replace(/[-:]/g, '').replace('T', 'T').split('.')[0] + 'Z';
    const slug = text
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .slice(0, 40)
      .replace(/-+$/, '') || 'note';
    const filename = `${ts}-${slug}.md`;
    const filepath = path.join(inboxPath, filename);

    const content = `- [stated] ${text}\n`;
    fs.writeFileSync(filepath, content);

    return NextResponse.json({
      ok: true,
      file: filename,
      message: `Captured to inbox/${filename}`,
    });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
