import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {TelegramWorkspace} from "@/components/telegram-workspace";
import type {TelegramState} from "@/lib/telegrams";
export const dynamic="force-dynamic";
export const metadata={title:"Telegrams"};
export default async function Telegrams(){
 await requireUser("/telegrams");
 const {data,error}=await (await createClient()).rpc("telegram_state");
 if(error||!data)return <section className="control-layout"><h1>Telegrams are unavailable</h1><p>Reconnect to the city to open your private mailbox.</p><a className="button" href="/telegrams">Try again</a></section>;
 return <TelegramWorkspace initial={data as TelegramState}/>;
}

