import { NextRequest, NextResponse } from 'next/server';
import { listVaultFiles } from '@/lib/vault';

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const category = searchParams.get('category');
  
  try {
    let files = listVaultFiles();
    if (category) {
      files = files.filter(f => f.category === category);
    }
    // Sort: areas first, then alphabetically within category
    const catOrder = ['profile', 'areas', 'people', 'projects', 'topics', 'daily'];
    files.sort((a, b) => {
      const ai = catOrder.indexOf(a.category);
      const bi = catOrder.indexOf(b.category);
      if (ai !== bi) return ai - bi;
      return a.name.localeCompare(b.name);
    });
    return NextResponse.json(files);
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}