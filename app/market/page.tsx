import Link from "next/link";
import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {MarketWorkspace} from "@/components/market-workspace";
import {LogoutButton} from "@/components/logout-button";
import type {MarketState,MarketView} from "@/lib/market";
export const dynamic="force-dynamic";
export const metadata={title:"Market"};
export default async function Market({searchParams}:{searchParams:Promise<{view?:string;good?:string;district?:string}>}){
 await requireUser("/market");
 const query=await searchParams;
 const {data,error}=await (await createClient()).rpc("market_state");
 if(error||!data)return <div className="control-layout"><h1>The exchange is temporarily unavailable</h1><p>Refresh to reconnect, or sign in again to restore your session.</p><Link href="/market">Try again</Link><LogoutButton/></div>;
 const views:MarketView[]=["floor","auctions","mine","inventory","orders"];
 return <MarketWorkspace initial={data as MarketState} initialView={views.includes(query.view as MarketView)?query.view as MarketView:"floor"} initialGood={query.good} initialDistrict={query.district}/>;
}
