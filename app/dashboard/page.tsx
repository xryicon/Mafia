import Link from "next/link";
import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {CommandDashboard} from "@/components/command-dashboard";
import {mailboxSummary} from "@/lib/dashboard";
export const dynamic="force-dynamic";
export const metadata={title:"Dashboard"};
export default async function Dashboard(){
 await requireUser("/dashboard");
 const client=await createClient();
 const [game,city,district,season,mailbox]=await Promise.all([
  client.rpc("game_state"),client.rpc("city_status"),client.rpc("district_state",{p_slug:"the-waterfront"}),
  client.rpc("season_state",{p_metric:"respect"}),client.rpc("telegram_state")
 ]);
 if(game.error||!game.data)return <section className="control-layout"><h1>Your dashboard could not be loaded</h1><p>Reconnect to Blackwater to see your empire.</p><Link className="button" href="/dashboard">Try again</Link></section>;
 return <CommandDashboard initial={{game:game.data,city:city.error?null:city.data,district:district.error?null:district.data,season:season.error?null:season.data,mailbox:mailbox.error||!mailbox.data?null:mailboxSummary(mailbox.data)}}/>;
}

