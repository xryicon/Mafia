import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { safeNext } from "@/lib/auth-paths";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  let path = "/login?error=invalid-link";
  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) path = safeNext(request.nextUrl.searchParams.get("next"));
  }
  const response = NextResponse.redirect(new URL(path, request.url));
  response.headers.set("Cache-Control", "private, no-store");
  response.headers.set("Referrer-Policy", "no-referrer");
  return response;
}
