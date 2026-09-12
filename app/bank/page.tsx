import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {BankWorkspace} from "@/components/bank-workspace";
import type {BankState} from "@/lib/bank";
export const dynamic="force-dynamic";
export const metadata={title:"National Bank"};
export default async function Page(){
 await requireUser("/bank");
 const r=await(await createClient()).rpc("bank_state",{p_offset:0});
 if(r.error||!r.data)throw new Error("The bank could not be loaded. Please refresh.");
 return <BankWorkspace initial={r.data as BankState}/>;
}
