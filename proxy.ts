import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { supabaseConfig } from "@/lib/supabase/config";
import { isProtectedPage, safeNext } from "@/lib/auth-paths";

export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });
  const { url, key } = supabaseConfig();
  const supabase = createServerClient(url, key, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll(values, headers) {
        values.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        values.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
        Object.entries(headers ?? {}).forEach(([name, value]) => response.headers.set(name, value));
      },
    },
  });
  const { data, error } = await supabase.auth.getClaims();
  if ((error || !data?.claims) && isProtectedPage(request.nextUrl.pathname)) {
    const destination = new URL("/login", request.url);
    destination.searchParams.set("next", safeNext(request.nextUrl.pathname));
    const redirected = NextResponse.redirect(destination);
    response.cookies.getAll().forEach(cookie => redirected.cookies.set(cookie));
    response = redirected;
  }
  response.headers.set("Cache-Control", "private, no-store");
  return response;
}

// Public forms must render even if session refresh or deployment configuration fails.
// Protected pages and the API still validate users independently on the server.
export const config = {
  matcher: ["/refineries/:path*", "/bin-diving/:path*", "/telegrams/:path*", "/ledger/:path*", "/market/:path*", "/properties/:path*", "/districts/:path*", "/gangs/:path*", "/profile/:path*", "/owner/:path*", "/support/:path*", "/account/:path*", "/seasons/:path*", "/players/:path*", "/staff/:path*", "/community/:path*", "/dashboard/:path*", "/update-password", "/api/:path*", "/auth/:path*"],
};
