import {NextResponse,type NextRequest} from "next/server";
import {createClient} from "@/lib/supabase/server";
import {confirmationToken,CONFIRMED_PATH} from "@/lib/confirmation";
export async function GET(request:NextRequest){
 let destination=CONFIRMED_PATH+"?error=invalid-link";
 const token_hash=confirmationToken(request.nextUrl.searchParams);
 if(token_hash){
  try{
   const supabase=await createClient();
   const {data,error}=await supabase.auth.verifyOtp({token_hash,type:"email"});
   if(!error&&data.session&&data.user?.email_confirmed_at)destination=CONFIRMED_PATH;
  }catch{console.warn("Email confirmation service unavailable");}
 }
 const response=NextResponse.redirect(new URL(destination,request.url));
 response.headers.set("Cache-Control","private, no-store");
 response.headers.set("Referrer-Policy","no-referrer");
 response.headers.set("X-Robots-Tag","noindex, nofollow");
 return response;
}
