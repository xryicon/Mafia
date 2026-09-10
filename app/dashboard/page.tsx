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
  if (error || !data) throw new Error("The city could not be loaded. Please retry.");
  return <GameShell initial={data as GameState} />;
}
