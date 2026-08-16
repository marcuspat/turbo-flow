import { NextRequest, NextResponse } from 'next/server';
import path from 'path';
import { readVaultFile } from '@/lib/vault';

export async function GET(request: NextRequest) {
  const name = request.nextUrl.searchParams.get('name');
  if (!name) {
    return NextResponse.json({ error: 'name is required' }, { status: 400 });
  }

  const safeName = path.basename(name);
  if (safeName !== name || safeName.includes('..')) {
    return NextResponse.json({ error: 'invalid name' }, { status: 400 });
  }

  try {
    const data = readVaultFile(name);
    if (!data) {
      return NextResponse.json({ error: 'not found' }, { status: 404 });
    }
    return NextResponse.json(data);
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
