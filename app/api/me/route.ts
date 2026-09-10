import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";
export async function GET() {
  const supabase = await createClient();
  const { data: { user }, error } = await supabase.auth.getUser();
  const headers = { "Cache-Control": "private, no-store" };
  if (error || !user) return NextResponse.json({ error: "Unauthorized" }, { status: 401, headers });
  return NextResponse.json({ id: user.id, email: user.email }, { headers });
}
