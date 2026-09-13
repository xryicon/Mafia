import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {GangWorkspace} from "@/components/gang-workspace";
import type {GangWorkspaceState} from "@/lib/gangs";
export const dynamic="force-dynamic";
export const metadata={title:"Gangs"};
export default async function Gangs({searchParams}:{searchParams:Promise<{gang?:string;tab?:string}>}){
 const p=await searchParams;const gang=typeof p.gang==="string"&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(p.gang)?p.gang:null;
 await requireUser("/gangs"+(gang?"?gang="+gang:""));
 const {data,error}=await(await createClient()).rpc("gang_workspace",{p_gang:gang,p_offset:0});
 if(error||!data)throw new Error("The gang headquarters could not be loaded.");
 return <GangWorkspace key={gang??"mine"} initial={data as GangWorkspaceState} initialTab={p.tab}/>;
}
