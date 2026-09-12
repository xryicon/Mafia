"use client";
import {useState,type FormEvent} from "react";
import {createClient} from "@/lib/supabase/client";
export function ResendConfirmation(){
 const [busy,setBusy]=useState(false),[message,setMessage]=useState("");
 async function resend(event:FormEvent<HTMLFormElement>){
  event.preventDefault();if(busy)return;
  const email=String(new FormData(event.currentTarget).get("email")||"").trim();
  setBusy(true);setMessage("");
  try{
   const {error}=await createClient().auth.resend({type:"signup",email,options:{emailRedirectTo:window.location.origin+"/auth/callback?next=/auth/confirmed"}});
   setMessage(error?"Unable to send a new link right now. Wait a minute and try again.":"If this account is waiting for confirmation, a new link is on its way. Check your inbox and spam folder.");
  }catch{setMessage("Unable to send a new link right now. Please try again later.");}
  finally{setBusy(false);}
 }
 return <details className="confirmation-resend"><summary>Need a new confirmation link?</summary><form onSubmit={resend}><label htmlFor="confirmation-email">Email address<input id="confirmation-email" name="email" type="email" autoComplete="email" required maxLength={254}/></label><button disabled={busy} type="submit">{busy?"Sending…":"Send a new confirmation link"}</button>{message&&<p role="status">{message}</p>}</form></details>;
}
