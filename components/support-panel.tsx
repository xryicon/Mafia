"use client";
import {useCallback,useEffect,useState,type FormEvent} from "react";
import {createClient} from "@/lib/supabase/client";
type Case={id:string;kind:string;subject:string;body:string;status:string;response:string|null;created_at:string};
type Sanction={id:string;kind:string;reason:string;expires_at:string|null;revoked_at:string|null};
export type SupportState={cases:Case[];sanctions:Sanction[]};
export function SupportPanel({initial}:{initial:SupportState}){
 const [data,setData]=useState(initial),[busy,setBusy]=useState(false),[notice,setNotice]=useState(""),[failed,setFailed]=useState(false);
 const refresh=useCallback(async()=>{const {data,error}=await createClient().rpc("support_state");if(error||!data)throw new Error("Could not refresh your tickets.");setData(data);},[]);
 useEffect(()=>{const timer=window.setInterval(()=>{if(!document.hidden)refresh().catch(()=>{});},30000);return ()=>window.clearInterval(timer);},[refresh]);
 async function submit(e:FormEvent<HTMLFormElement>){
  e.preventDefault();if(busy)return;const form=e.currentTarget,payload=Object.fromEntries(new FormData(form));setBusy(true);setNotice("");setFailed(false);
  try{const {data:result,error}=await createClient().rpc("community_action",{action:"ticket",payload});if(error||result?.error)throw new Error(result?.error||"Could not create your ticket.");
   form.reset();setNotice("Ticket created. The team will reply here.");await refresh();
  }catch(e){setFailed(true);setNotice(e instanceof Error?e.message:"Ticket could not be created.");}finally{setBusy(false);}
 }
 return <div className="control-layout support-page"><div className="control-heading"><div><p className="eyebrow">BLACKWATER / SUPPORT</p><h1>A direct line to the team.</h1><p>Account trouble, a game issue, or something we should know about? Open a private ticket.</p></div></div>{notice&&<p className={"notice"+(failed?" error":"")} role={failed?"alert":"status"}>{notice}</p>}
 <div className="support-grid"><form className="control-card support-form" onSubmit={submit}><p className="eyebrow">WE'RE HERE TO HELP</p><h2>Create a ticket</h2><label>Subject<input name="subject" required minLength={3} maxLength={160} placeholder="What can we help with?"/></label><label>Details<textarea name="body" required minLength={3} maxLength={4000} rows={7} placeholder="Tell us what happened and what you expected."/></label><p className="hint">Only you and authorized staff can view your ticket. Never include your password.</p><button className="button" disabled={busy}>{busy?"Creating…":"Create ticket ↗"}</button></form>
 <section className="support-history"><div className="panel-heading"><h2>Your tickets</h2><button className="button small ghost" onClick={()=>refresh().catch(e=>{setFailed(true);setNotice(e.message);})}>Refresh tickets</button></div>{data.cases.length?data.cases.map(c=><article className="control-card support-ticket" key={c.id}><div className="ticket-meta"><span>{c.kind==="report"?"Report":"Ticket"}</span><span className="ticket-status">{c.status}</span></div><h3>{c.subject}</h3><p className="preserve-text">{c.body}</p><small>{new Date(c.created_at).toLocaleDateString("en-GB",{day:"numeric",month:"short",year:"numeric",timeZone:"UTC"})}</small>{c.response&&<div className="ticket-response"><strong>Staff reply</strong><p className="preserve-text">{c.response}</p></div>}</article>):<div className="control-card support-empty"><span>◈</span><h3>Nothing waiting here.</h3><p>Your tickets and replies will appear here.</p></div>}</section></div>
 {data.sanctions.length>0&&<section><h2>Account notices</h2>{data.sanctions.map(s=><article className="control-card" key={s.id}><h3>{s.kind}</h3><p>{s.reason}</p><small>{s.revoked_at?"Revoked":s.expires_at?"Expires "+new Date(s.expires_at).toLocaleString():"No expiry"}</small></article>)}</section>}</div>;
}
