import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {RefineryWorkspace} from "@/components/refinery-workspace";
import type {RefineryState} from "@/lib/refineries";
export const dynamic="force-dynamic";
export const metadata={title:"Refineries"};
export default async function Page({searchParams}:{searchParams:Promise<{plot?:string}>}){
 await requireUser("/refineries");
 const r=await(await createClient()).rpc("refinery_state");
 if(r.error||!r.data)throw new Error("Refineries could not be loaded. Please refresh.");
 return <RefineryWorkspace initial={r.data as RefineryState} initialPlot={(await searchParams).plot}/>;
}
