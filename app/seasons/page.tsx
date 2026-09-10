import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {SeasonPanel} from "@/components/season-panel";
import type {SeasonState} from "@/lib/seasons";
export const dynamic="force-dynamic";
export const metadata={title:"Seasons & leaderboards"};
export default async function Seasons(){
 await requireUser("/seasons");
 const {data,error}=await (await createClient()).rpc("season_state");
 if(error||!data)throw new Error("Seasons could not be loaded.");
 return <SeasonPanel initial={data as SeasonState}/>;
}
