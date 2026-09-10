import Link from "next/link";
import { requireUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { CommunityPanel, type CommunityState } from "@/components/community-panel";
export const dynamic="force-dynamic";
export const metadata={title:"Community"};
export default async function Community(){
 const user=await requireUser("/community");const db=await createClient();
 const initialized=await db.rpc("game_state");
 if(initialized.error)return <main className="control-layout"><h1>Account access restricted</h1><p>Sign in again. If access remains suspended, contact the game Owner.</p><Link href="/login">Sign in</Link></main>;
 const {data,error}=await db.rpc("community_state");
 if(error||!data)throw new Error("Community could not be loaded.");
 return <CommunityPanel initial={data as CommunityState} playerId={user.id}/>;
}