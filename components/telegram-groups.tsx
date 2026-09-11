"use client";
import {useEffect,useRef,useState,type FormEvent} from "react";
import Link from "next/link";
import {GameIcon} from "@/components/game-icon";
import {PlayerAvatar} from "@/components/player-avatar";
import type {TelegramState} from "@/lib/telegrams";
export type RoomAction=(action:string,payload?:Record<string,unknown>)=>Promise<{thread_id:string;message:string}|null>;
export function NewTelegramGroup({open,onClose,limit,run,busy,notice,retry}:{notice:string;retry:boolean;open:boolean;onClose:()=>void;limit:number;run:RoomAction;busy:boolean}){
 const ref=useRef<HTMLDialogElement>(null),[name,setName]=useState("");
 useEffect(()=>{if(open){setName("");ref.current?.showModal();}else ref.current?.close();},[open]);
 async function submit(e:FormEvent){e.preventDefault();if(await run("create",{name}))onClose();}
 return <dialog className="tg-modal tg-group-modal" ref={ref} onCancel={()=>!busy&&onClose()} aria-labelledby="tg-group-title"><header><div><p className="eyebrow">A PRIVATE TABLE</p><h2 id="tg-group-title">Create a group</h2></div><button type="button" aria-label="Close group creation" disabled={busy} onClick={onClose}>×</button></header><p>Bring your trusted contacts together. Players choose whether to accept your invitation.</p>{notice&&<p className="tg-group-result" role="status">{notice}</p>}{retry&&<button onClick={()=>void run("")}>Retry group change</button>}<form onSubmit={submit}><label>Group name<input value={name} onChange={e=>setName(e.target.value)} minLength={3} maxLength={limit} required autoFocus disabled={busy} placeholder="e.g. Waterfront Trading Circle"/></label><p className="hint">Invite players after creating the group. Messages use the existing office fee once per telegram.</p><button className="tg-gold" disabled={busy}>{busy?"Creating…":"Create group"}</button></form></dialog>;
}
export function TelegramMembers({data,run,busy,onClose}:{data:TelegramState;run:RoomAction;busy:boolean;onClose:()=>void}){
 const t=data.thread,[username,setUsername]=useState(""),[name,setName]=useState(t?.other_name||"");
 if(!t||t.kind==="direct"||!t.kind)return null;
 return <section className="tg-members" aria-label="Conversation members"><header><div><span className="eyebrow">{t.kind==="gang"?"GANG ROSTER":"PRIVATE GROUP"}</span><h3>{t.member_count} members</h3></div><button type="button" aria-label="Close members" onClick={onClose}>×</button></header>{t.kind==="gang"?<p>Access follows your current gang membership. New members receive future telegrams; leaving the gang removes access.</p>:<p>Only members can read this conversation. New members receive messages sent after they join.</p>}
 <ul>{data.members?.map(m=><li key={m.id}><PlayerAvatar src={m.avatar_url} name={m.name} className="tg-seal" size={34}/><span><Link href={"/players/"+m.id}>{m.name}</Link><small>{m.owner?"Group owner":m.status==="invited"?"Invitation pending":"Member"}</small></span>{t.can_manage&&m.id!==data.player_id&&<details><summary aria-label={"Manage "+m.name}>⋮</summary><div><button disabled={busy} onClick={()=>void run("remove",{thread_id:t.id,player_id:m.id})}>{m.status==="invited"?"Cancel invitation":"Remove member"}</button>{m.status==="active"&&<button disabled={busy} onClick={()=>void run("transfer",{thread_id:t.id,player_id:m.id})}>Make group owner</button>}</div></details>}</li>)}</ul>
 {t.can_manage&&<><form onSubmit={async e=>{e.preventDefault();if(await run("invite",{thread_id:t.id,username}))setUsername("");}}><label>Invite player<input value={username} onChange={e=>setUsername(e.target.value)} maxLength={48} required placeholder="Exact player username" disabled={busy}/></label><button disabled={busy}><GameIcon name="people" size={16}/>Send invitation</button></form><details className="tg-group-settings"><summary>Group settings</summary><form onSubmit={async e=>{e.preventDefault();await run("rename",{thread_id:t.id,name});}}><label>Group name<input value={name} onChange={e=>setName(e.target.value)} minLength={3} maxLength={data.limits.group_name??60} required disabled={busy}/></label><button disabled={busy}>Rename group</button></form><p>To leave, make another active member the group owner first.</p></details></>}
 {t.kind==="group"&&!t.can_manage&&<button disabled={busy} onClick={()=>void run("leave",{thread_id:t.id})}>Leave group</button>}
 </section>;
}

