import {notFound} from "next/navigation";
import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {PlayerProfileView} from "@/components/player-profile";
import type {PlayerProfile} from "@/lib/player-profile";
export const dynamic="force-dynamic";
export const metadata={title:"Player profile",robots:{index:false,follow:false}};
export default async function Profile({params}:{params:Promise<{id:string}>}){
 const {id}=await params;await requireUser("/players/"+id);
 if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(id))notFound();
 const {data,error}=await (await createClient()).rpc("player_profile",{p_player:id});
 if(error)throw new Error("This profile could not be loaded. Please try again.");if(!data)notFound();
 return <PlayerProfileView initial={data as PlayerProfile}/>;
}
