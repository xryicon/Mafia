"use client";
import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";
import { USERNAME_PATTERN, usernameError } from "@/lib/usernames";
export function UsernameForm({onSaved}:{onSaved?:()=>void}) {
 const [busy,setBusy]=useState(false),[error,setError]=useState("");
 async function submit(e:FormEvent<HTMLFormElement>){
  e.preventDefault(); if(busy)return;
  const name=String(new FormData(e.currentTarget).get("username")??"").trim(),invalid=usernameError(name);
  if(invalid){setError(invalid);return;}
  setBusy(true);setError("");
  try{
   const {data,error}=await createClient().rpc("claim_username",{candidate:name});
   if(error||data?.error)throw new Error(data?.error||"Could not save your username. Try again.");
   window.dispatchEvent(new Event("blackwater:identity"));
   if(onSaved)onSaved();else window.location.reload();
  }catch(e){setError(e instanceof Error?e.message:"Could not save your username.");}
  finally{setBusy(false);}
 }
 return <form className="username-form" onSubmit={submit}><label>Your username<input name="username" autoComplete="nickname" required minLength={3} maxLength={24} pattern={USERNAME_PATTERN} placeholder="Make a name for yourself"/></label><p className="hint">3–24 characters, starting with a letter. Your name appears in chat, trading and rankings. Choose carefully; Support can help with future changes.</p>{error&&<p role="alert" className="notice error">{error}</p>}<button className="button full" disabled={busy}>{busy?"Saving…":"Claim my name"}</button></form>;
}
