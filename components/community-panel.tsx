"use client";
import { useState, type FormEvent } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
type Row=Record<string,string|null>;
export type CommunityState={chat:Row[];cases:Row[];sanctions:Row[]};
export function CommunityPanel({initial,playerId}:{initial:CommunityState;playerId:string}){
 const [state,setState]=useState(initial),[notice,setNotice]=useState(""),[busy,setBusy]=useState(false);
 async function send(action:string,payload:Record<string,string>){
  if(busy)return;setBusy(true);
  try{const {data,error}=await createClient().rpc("community_action",{action,payload});if(error||data?.error)throw new Error(data?.error||error?.message);
  setNotice(data.message);await refresh();}catch(e){setNotice(e instanceof Error?e.message:"Could not save.");}finally{setBusy(false);}
 }
 async function refresh(){const {data,error}=await createClient().rpc("community_state");if(error)throw new Error(error.message);setState(data);}
 async function submit(e:FormEvent<HTMLFormElement>){e.preventDefault();const f=Object.fromEntries(new FormData(e.currentTarget)) as Record<string,string>;await send(f.action,f);}
 return <main className="control-layout"><div className="control-heading"><div><p className="eyebrow">BLACKWATER / COMMUNITY</p><h1>The city speaks.</h1></div><Link className="button ghost" href="/dashboard">Return to empire</Link></div>
 {notice&&<p className="game-notice" role="status">{notice}</p>}
 <div className="control-grid"><section className="control-card"><h2>City chat</h2><form onSubmit={submit}><input type="hidden" name="action" value="chat"/><label>Message<textarea name="body" required maxLength={1000}/></label><button className="button small" disabled={busy}>Send message</button></form><button className="link-button" onClick={()=>refresh().catch(()=>setNotice("Refresh failed. Try again."))}>Refresh messages</button>{state.chat.map(c=><article className="chat-message" key={c.id}><strong>{c.handle}</strong><p className="preserve-text">{c.body}</p>{c.player_id===playerId&&<button className="link-button" disabled={busy} onClick={()=>send("delete_own_chat",{id:c.id!})}>Remove message</button>}</article>)}</section>
 <section className="control-card"><h2>Reports and support</h2><form onSubmit={submit}><label>Request type<select name="action"><option value="ticket">Support ticket</option><option value="report">Report a player or message</option></select></label><label>Subject<input name="subject" required minLength={3} maxLength={160}/></label><label>Details<textarea name="body" required minLength={3} maxLength={4000}/></label><button className="button small" disabled={busy}>Submit request</button></form><h3>Your requests</h3>{state.cases.map(c=><article className="chat-message" key={c.id}><strong>{c.subject} · {c.status}</strong><p className="preserve-text">{c.body}</p>{c.response&&<p className="preserve-text">Staff response: {c.response}</p>}<button className="link-button" disabled={busy} onClick={()=>send("delete_own_case",{id:c.id!})}>Remove from my view</button></article>)}</section></div>
 {!!state.sanctions.length&&<section><h2>Account notices</h2>{state.sanctions.map(s=><p className="control-card" key={s.id}>{s.kind}: {s.reason} · {s.revoked_at?"Revoked":s.expires_at?"Expires "+s.expires_at:"No expiry"}</p>)}</section>}</main>;
}