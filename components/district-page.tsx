import {DistrictTravelGate} from "./district-travel";
import Link from "next/link";
import {PrisonDistrict} from "./prison-district";
import {PRISON_PATH,type PrisonState} from "@/lib/prison";
import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {DistrictExplorer} from "@/components/district-explorer";
import type {DistrictState} from "@/lib/districts";
import {MiningDistrict} from "@/components/mining-district";
import type {MiningState} from "@/lib/mining";
export async function DistrictPage({slug,registry=false}:{slug?:string;registry?:boolean}){
 await requireUser(slug?"/districts/"+slug:"/districts");
 if(slug==="blackwater-island"){const {data,error}=await (await createClient()).rpc("prison_state");if(error||!data)return <section className="control-layout"><h1>The prison could not be loaded</h1><p>Refresh to reconnect to the prison register.</p><Link href={PRISON_PATH}>Try again</Link></section>;return <DistrictTravelGate target={slug}><PrisonDistrict initial={data as PrisonState}/></DistrictTravelGate>;}
const {data,error}=await (await createClient()).rpc("district_state",{p_slug:slug??null});
 if(error||!data)return <section className="control-layout"><h1>The district could not be loaded</h1><p>Refresh to reconnect to the city.</p><Link href="/districts">Back to City Map</Link></section>;
 if(data.district?.district_type==="mining"&&!registry){const mine=await (await createClient()).rpc("mining_state",{p_slug:slug});if(mine.error||!mine.data)return <section className="control-layout"><h1>The mines could not be loaded</h1><p>Refresh to reconnect to the mining registry.</p><Link href="/districts">Back to City Map</Link></section>;return <DistrictTravelGate target={data.district.id}><MiningDistrict initial={mine.data as MiningState}/></DistrictTravelGate>;}
 return slug?<DistrictTravelGate target={slug}><DistrictExplorer initial={data as DistrictState} slug={slug}/></DistrictTravelGate>:<DistrictExplorer initial={data as DistrictState} slug={slug}/>;
}
