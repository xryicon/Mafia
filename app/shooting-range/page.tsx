import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {RangeWorkspace} from "@/components/range-workspace";
import type {RangeState} from "@/lib/range";
export const dynamic="force-dynamic";
export const metadata={title:"Shooting Range"};
export default async function Range(){await requireUser("/shooting-range");const r=await(await createClient()).rpc("range_state");if(r.error||!r.data)throw new Error("The shooting range could not load. Please refresh.");return <RangeWorkspace initial={r.data as RangeState}/>;}
