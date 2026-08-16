import { NextResponse } from 'next/server';
import { getDoctorData } from '@/lib/vault';

export async function GET() {
  try {
    const data = getDoctorData();
    return NextResponse.json(data);
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
