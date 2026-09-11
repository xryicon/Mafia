import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {PlayerDirectory} from "@/components/player-directory";
import type {DirectoryState} from "@/lib/social";
export const dynamic="force-dynamic";
export const metadata={title:"Players & respect"};
export default async function Players({searchParams}:{searchParams:Promise<{online?:string}>}){
 await requireUser("/players");const online=(await searchParams).online==="1";
 const {data,error}=await (await createClient()).rpc("player_directory",{p_search:"",p_online:online,p_offset:0});
 if(error||!data)throw new Error("Players could not be loaded.");
 return <PlayerDirectory initial={data as DirectoryState} initialOnline={online}/>;
}
