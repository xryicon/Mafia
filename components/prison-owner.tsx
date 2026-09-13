"use client";
import {useCallback,useEffect,useState} from "react";
import {createClient} from "@/lib/supabase/client";
import type {StaffState} from "./staff-panel";
import type {PrisonSentence} from "@/lib/prison";
type Inmate=PrisonSentence&{player_id:string;handle:string};
export function PrisonOwner({players}:{players:StaffState["players"]}){
 const [rows,setRows]=useState<Inmate[]>([]),[notice,setNotice]=useState(""),[busy,setBusy]=useState(false);
 const refresh=useCallback(async()=>{const {data,error}=await createClient().rpc("prison_manage",{p_action:"list"});if(error)throw new Error(error.message);setRows(data.sentences);},[]);
 useEffect(()=>{void refresh().catch(e=>setNotice(e.message));},[refresh]);
 async function act(action:string,payload:Record<string,string>){setBusy(true);setNotice("");try{const {data,error}=await createClient().rpc("prison_manage",{p_action:action,p_payload:payload});if(error||data?.error)throw new Error(error?.message||data.error);setNotice(data.message);await refresh();window.dispatchEvent(new Event("blackwater:game"));}catch(e){setNotice(e instanceof Error?e.message:"Prison action could not be confirmed. Refresh the register before retrying.");}finally{setBusy(false);}}
 return <section className="control-layout"><p className="eyebrow">BLACKWATER ISLAND</p><h2>Prison administration</h2><p>Issue a timed sentence or authorize an early release. Every change is recorded in the audit history.</p>{notice&&<p role="status">{notice}</p>}
 <form className="control-card" onSubmit={e=>{e.preventDefault();void act("jail",Object.fromEntries(new FormData(e.currentTarget)) as Record<string,string>);}}><fieldset disabled={busy}><legend>Send a player to prison</legend><label>Player<select aria-label="Player" name="player_id" required defaultValue=""><option value="" disabled>Choose a player</option>{players.map(p=><option key={String(p.id)} value={String(p.id)}>{String(p.handle||p.id)}</option>)}</select></label><label>Sentence (minutes)<input name="minutes" type="number" min="1" max="10080" defaultValue="10" required/></label><label>Reason for imprisonment<input name="reason" required minLength={3} maxLength={2000}/></label><button className="button" type="submit">Send to Blackwater Island</button></fieldset></form>
 <h3>Current inmates</h3><button disabled={busy} onClick={()=>void refresh().catch(e=>setNotice(e.message))}>Refresh prison register</button><div className="prison-register">{rows.map(p=><article key={p.id}><h3>{p.handle}</h3><p>{p.reason}</p><p>Scheduled release: {new Date(p.release_at).toLocaleString()}</p><form onSubmit={e=>{e.preventDefault();void act("release",{player_id:p.player_id,sentence_id:p.id,...Object.fromEntries(new FormData(e.currentTarget))});}}><label>Reason for early release<input name="reason" minLength={3} maxLength={2000} required/></label><button disabled={busy} className="button">Release player</button></form></article>)}{!rows.length&&<p>No players are currently in custody.</p>}</div></section>;
}

