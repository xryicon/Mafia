import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {BinDiving} from "@/components/bin-diving";
import type {BinState} from "@/lib/bin-diving";
export const dynamic="force-dynamic";
export const metadata={title:"Bin Diving | Blackwater Mafia"};
export default async function Page({searchParams}:{searchParams:Promise<{district?:string}>}){
 await requireUser("/bin-diving");
 const r=await (await createClient()).rpc("bin_diving_state");
 if(r.error||!r.data)throw new Error("Bin diving could not load. Please try again.");
 return <BinDiving initial={r.data as BinState} initialDistrict={(await searchParams).district}/>;
}
