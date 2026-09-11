import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {SupportPanel,type SupportState} from "@/components/support-panel";
export const dynamic="force-dynamic";
export const metadata={title:"Support"};
export default async function Support(){
 await requireUser("/support");
 const {data,error}=await (await createClient()).rpc("support_state");
 if(error||!data)throw new Error("Support could not be loaded.");
 return <SupportPanel initial={data as SupportState}/>;
}
