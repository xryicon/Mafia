import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {ChopShop} from "@/components/chop-shop";
export const dynamic="force-dynamic";
export const metadata={title:"Chop shop"};
export default async function Page(){await requireUser("/chop-shop");const r=await(await createClient()).rpc("chop_shop_state");if(r.error||!r.data)throw new Error("Chop shops could not load. Please refresh.");return <ChopShop initial={r.data}/>;}
