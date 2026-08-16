import { NextRequest, NextResponse } from 'next/server';
import { searchVault } from '@/lib/vault';

export async function GET(request: NextRequest) {
  const query = request.nextUrl.searchParams.get('q');
  if (!query) {
    return NextResponse.json({ error: 'q is required' }, { status: 400 });
  }

  try {
    const hits = searchVault(query);
    return NextResponse.json({ query, hits, count: hits.length });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
