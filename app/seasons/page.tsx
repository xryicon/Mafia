import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {SeasonPanel} from "@/components/season-panel";
import type {SeasonState} from "@/lib/seasons";
export const dynamic="force-dynamic";
export const metadata={title:"Seasons & leaderboards"};
export default async function Seasons({searchParams}:{searchParams:Promise<{season?:string;metric?:string}>}){
 await requireUser("/seasons");
 const query=await searchParams,season=typeof query.season==="string"&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(query.season)?query.season:null,metric=typeof query.metric==="string"&&/^[a-z_]{2,48}$/.test(query.metric)?query.metric:"net_worth";
 const {data,error}=await (await createClient()).rpc("season_state",{p_season:season,p_metric:metric});
 if(error||!data)throw new Error("Seasons could not be loaded.");
 return <SeasonPanel key={season+":"+metric} initial={data as SeasonState}/>;
}
