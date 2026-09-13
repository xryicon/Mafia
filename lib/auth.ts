import "server-only";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PRISON_PATH, prisonAllowsPath } from "@/lib/prison";
import { safeNext } from "@/lib/auth-paths";

export async function requireUser(next = "/dashboard") {
  const supabase = await createClient();
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) redirect("/login?next=" + encodeURIComponent(safeNext(next)));
  if (!prisonAllowsPath(next)) {
    const custody=await supabase.rpc("prison_state");
    if(custody.error) throw new Error("Could not verify prison status. Please refresh.");
    if(custody.data?.jailed) redirect(PRISON_PATH);
  }
  return user;
}
