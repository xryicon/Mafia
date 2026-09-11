import Link from "next/link";
import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {OwnerWorkspace} from "@/components/owner-workspace";
import type {StaffState} from "@/components/staff-panel";
import type {SeasonState} from "@/lib/seasons";
export const dynamic="force-dynamic";
export const metadata={title:"Owner panel"};
export default async function Owner({searchParams}:{searchParams:Promise<{section?:string}>}){
 await requireUser("/owner");const db=await createClient();const staff=await db.rpc("staff_state");
 if(staff.error||!staff.data?.permissions?.includes("roles.manage"))return <div className="control-layout"><h1>Owner access required</h1><p>This office is reserved for the game Owner.</p><Link href="/dashboard">Return to empire</Link></div>;
 const seasons=await db.rpc("season_state");if(seasons.error||!seasons.data)throw new Error("Owner controls could not be loaded.");
 return <OwnerWorkspace staff={staff.data as StaffState} seasons={seasons.data as SeasonState} initialSection={(await searchParams).section}/>;
}
