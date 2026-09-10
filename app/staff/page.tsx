import Link from "next/link";
import { requireUser } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { StaffPanel, type StaffState } from "@/components/staff-panel";
export const dynamic="force-dynamic";
export const metadata={title:"City Hall"};
export default async function Staff(){
 await requireUser("/staff");
 const {data,error}=await (await createClient()).rpc("staff_state");
 if(error||!data)return <main className="control-layout"><h1>Staff access required</h1><p>Your account does not currently have access, or your session has expired.</p><Link href="/dashboard">Return to empire</Link></main>;
 return <StaffPanel initial={data as StaffState}/>;
}