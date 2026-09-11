import Link from "next/link";
import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {DistrictExplorer} from "@/components/district-explorer";
import type {DistrictState} from "@/lib/districts";
export async function DistrictPage({slug}:{slug?:string}){
 await requireUser("/districts");const {data,error}=await (await createClient()).rpc("district_state",{p_slug:slug??null});
 if(error||!data)return <section className="control-layout"><h1>The district could not be loaded</h1><p>Refresh to reconnect to the city.</p><Link href="/districts">Back to City Map</Link></section>;
 return <DistrictExplorer initial={data as DistrictState} slug={slug}/>;
}
