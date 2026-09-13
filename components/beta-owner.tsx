"use client";

import {useEffect,useState,type FormEvent} from "react";
import {createClient} from "@/lib/supabase/client";

function localInput(unix:number){
 const date=new Date(unix*1000);return new Date(date.getTime()-date.getTimezoneOffset()*60000).toISOString().slice(0,16);
}
function displayDate(value:string){
 const date=new Date(value);return Number.isNaN(date.getTime())?"Choose a launch date and time":new Intl.DateTimeFormat(undefined,{dateStyle:"full",timeStyle:"short"}).format(date);
}

export function BetaOwner({value,onSaved}:{value:number;onSaved:(value:number)=>void}){
 const [dateTime,setDateTime]=useState(()=>localInput(value)),[reason,setReason]=useState("Update closed beta launch schedule"),[notice,setNotice]=useState(""),[failed,setFailed]=useState(false),[busy,setBusy]=useState(false);
 useEffect(()=>setDateTime(localInput(value)),[value]);
 async function save(event:FormEvent<HTMLFormElement>){
  event.preventDefault();setNotice("");setFailed(false);
  const unix=Math.floor(new Date(dateTime).getTime()/1000);
  if(!Number.isFinite(unix)||unix<0||unix>2147483647){setFailed(true);setNotice("Choose a valid launch date and time before January 2038.");return;}
  setBusy(true);
  try{
   const {data,error}=await createClient().rpc("staff_action",{action:"setting",payload:{key:"closed_beta_starts_at_unix",value:String(unix),reason:reason.trim()}});
   if(error||data?.error)throw new Error(data?.error||error?.message||"The launch schedule could not be saved.");
   onSaved(unix);setNotice("Closed beta launch schedule saved. The landing-page countdown is now using this time.");
  }catch(error){setFailed(true);setNotice(error instanceof Error?error.message:"The launch schedule could not be saved.");}
  finally{setBusy(false);}
 }
 return <section className="beta-owner">
  <header><p className="eyebrow">PUBLIC LANDING PAGE</p><h2>Closed beta launch</h2><p>Choose the exact day and time shown on the public countdown. The time below uses your current device timezone.</p></header>
  {notice&&<p className={failed?"notice error":"notice"} role={failed?"alert":"status"}>{notice}</p>}
  <form className="control-card" onSubmit={save}>
   <label htmlFor="closed-beta-start">Closed beta date and time<input id="closed-beta-start" type="datetime-local" value={dateTime} max="2038-01-19T03:14" onChange={event=>setDateTime(event.target.value)} required/></label>
   <label htmlFor="closed-beta-reason">Reason for this change<input id="closed-beta-reason" value={reason} minLength={3} maxLength={2000} onChange={event=>setReason(event.target.value)} required/></label>
   <div className="beta-owner-preview"><span>Landing page will show</span><strong>{displayDate(dateTime)}</strong></div>
   <button className="button" type="submit" disabled={busy}>{busy?"Saving…":"Save launch schedule"}</button>
  </form>
 </section>;
}
