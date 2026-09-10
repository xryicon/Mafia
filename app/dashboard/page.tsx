import Link from "next/link";
import { LogoutButton } from "@/components/logout-button";
import { requireUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { GameShell } from "@/components/game-shell";
import type { GameState } from "@/lib/game";
export const dynamic = "force-dynamic";
export const metadata = { title: "Your empire" };
export default async function Dashboard() {
  await requireUser();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("game_state");
  if (error || !data) return <main className="control-layout"><h1>The city could not be loaded</h1><p>Your session may have been revoked or your account suspended. Sign out and sign in again. If access remains restricted, contact the game Owner.</p><LogoutButton/><Link href="/login">Sign in</Link></main>;
  return <GameShell initial={data as GameState} />;
}
