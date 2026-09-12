"use client";
import {useState,type FormEvent} from "react";
import {createClient} from "@/lib/supabase/client";
import {PlayerAvatar} from "@/components/player-avatar";
export function ProfilePicture({initial,name,onSaved}:{initial?:string|null;name:string;onSaved?:(src:string)=>void}){
 const [url,setUrl]=useState(initial?.startsWith("https://")?initial:""),[saved,setSaved]=useState(initial),[busy,setBusy]=useState(false),[notice,setNotice]=useState("");
 async function save(e:FormEvent<HTMLFormElement>){e.preventDefault();setBusy(true);setNotice("");try{const r=await createClient().rpc("profile_avatar",{p_url:url.trim()});if(r.error||r.data?.error)throw new Error(r.data?.error||r.error?.message);setSaved(r.data.avatar_url);onSaved?.(r.data.avatar_url);setNotice(r.data.message);window.dispatchEvent(new Event("blackwater:identity"));}catch(e){setNotice(e instanceof Error?e.message:"Picture could not be saved.");}finally{setBusy(false);}}
 return <section className="control-card profile-picture-card"><h2>Profile picture</h2><PlayerAvatar src={saved} name={name} className="profile-picture-preview" size={96}/><form onSubmit={save}><label>Profile image URL<input type="url" placeholder="https://…" value={url} onChange={e=>setUrl(e.target.value)} maxLength={2048}/></label><p className="hint">Paste an HTTPS image link. Leave it blank to use the Blackwater portrait. Your picture appears on your profile, dashboard and Telegrams.</p><button className="button ghost" disabled={busy}>{busy?"Saving…":"Save picture"}</button></form>{notice&&<p role="status">{notice}</p>}</section>;
}

