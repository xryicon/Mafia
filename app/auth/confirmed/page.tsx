import {createClient} from "@/lib/supabase/server";
import {ConfirmationScreen} from "@/components/confirmation-screen";
export const dynamic="force-dynamic";
export const metadata={title:"Account confirmation",robots:{index:false,follow:false}};
export default async function Confirmed({searchParams}:{searchParams:Promise<{error?:string}>}){
 const {error}=await searchParams;
 let verified=false;
 try{
  const supabase=await createClient();
  const {data,error:authError}=await supabase.auth.getUser();
  verified=!authError&&!!data.user?.email_confirmed_at;
 }catch{console.warn("Account confirmation status unavailable");}
 return <ConfirmationScreen state={error?"invalid":verified?"confirmed":"pending"}/>;
}
