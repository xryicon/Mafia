"use client";
import {useEffect,useRef,useState} from "react";
import {createPortal} from "react-dom";
import {CommodityArtwork} from "./commodity-artwork";
import {GameIcon} from "./game-icon";
import type {RobberyState} from "@/lib/robbery";
import "./robbery.css";
const countdown=(until:string|null,now:number)=>{const seconds=until?Math.max(0,Math.ceil((Date.parse(until)-now)/1000)):0;return seconds?`${Math.floor(seconds/60)}m ${seconds%60}s`:"";};
export function RobberyPanel({data,now,busy,blocked,act}:{data?:RobberyState;now:number;busy:boolean;blocked:boolean;act:(action:string,payload?:Record<string,unknown>)=>Promise<boolean>}){
 const [open,setOpen]=useState(false),[selected,setSelected]=useState(""),[notice,setNotice]=useState("");const dialog=useRef<HTMLDialogElement>(null);
 useEffect(()=>{if(open)dialog.current?.showModal();else dialog.current?.close();},[open]);
 if(!data)return null;
 const r=data.rules,w=data.weapon,target=data.targets.find(t=>t.id===selected),cooldown=countdown(data.ready_at,now),protection=countdown(data.protected_until,now);
 const ready=!blocked&&!busy&&data.available&&r.enabled&&!cooldown&&!!w&&w.ammo>=r.bullet_max;
 return <><button className="robbery-map-button" disabled={busy} onClick={()=>{setOpen(true);setNotice("");}}><GameIcon name="pistol" size={18}/> Players · {data.targets.length}</button>
 {open&&createPortal(<dialog ref={dialog} className="robbery-dialog" onCancel={e=>{if(busy)e.preventDefault();else setOpen(false);}} aria-labelledby="robbery-title">
 <header><div><p className="eyebrow">BLACKWATER / STREET OPERATIONS</p><h2 id="robbery-title">Players & robbery</h2></div><button aria-label="Close robbery panel" disabled={busy} onClick={()=>setOpen(false)}>×</button></header>
 <p>Rob players active in this district. Only carried cash is at risk. Bank deposits and inventory items stay with their owner.</p>
 <div className="robbery-summary"><span><b>{r.steal_min}–{r.steal_max}%</b> of carried cash on success</span><span><b>{r.bullet_min}–{r.bullet_max}</b> bullets, randomly used</span><span><b>{r.victim_cooldown_seconds/60} min</b> victim protection after every attempt</span></div>
 {data.factors&&<p className="robbery-factors">Your Sharpshooting: level {data.factors.level} · Advanced accuracy: {data.factors.accuracy.toFixed(1)}% · Power: {data.factors.power.toLocaleString()}</p>}
 {w?<div className="robbery-weapon"><CommodityArtwork goodId={w.good_id} size={64}/><div><strong>{w.name}</strong><p>Condition {w.condition}/{w.condition_max} · {w.ammo} compatible bullets equipped</p><small>Need {r.bullet_max} bullets available. Only the rolled amount is consumed; firing also wears your gun.</small></div></div>:<p className="robbery-warning">Equip a working gun in Inventory before attempting a robbery.</p>}
 {!r.enabled&&<p className="robbery-warning">Robberies are paused.</p>}{cooldown&&<p className="robbery-warning">Your next attempt: {cooldown}</p>}{protection&&<p>Your protection remaining: {protection}</p>}{!data.available&&<p>Stop walking and finish any search or range session to attempt a robbery.</p>}
 <div className="robbery-targets">{data.targets.length?data.targets.map(t=>{const protectedFor=countdown(t.protected_until,now);return <button key={t.id} className={selected===t.id?"selected":""} disabled={busy||!!protectedFor} onClick={()=>{setSelected(t.id);setNotice("");}}>{t.avatar_url&&<img src={t.avatar_url} alt="" width={44} height={44}/>}<span><strong>{t.handle}</strong><small>{t.power.toLocaleString()} power</small></span><span>{protectedFor?"Protected · "+protectedFor:t.chance.toFixed(1)+"% success"}</span></button>;}):<p className="robbery-empty">No available players nearby. Players appear while active and stationary on this district’s Scavenging map.</p>}</div>
 {target&&<section className="robbery-confirm"><h3>Rob {target.handle}?</h3><p>Success chance: {target.chance.toFixed(1)}%. Sharpshooting, advanced accuracy, power and both players’ equipped gear are compared again on the server.</p><p>A failed attempt still uses bullets and triggers cooldowns. Your cooldown lasts {r.attacker_cooldown_seconds/60} minutes. No health damage is dealt by this action.</p><button className="bin-gold" disabled={!ready||!!countdown(target.protected_until,now)} onClick={async()=>{setNotice("");if(await act("rob_attempt",{target_id:target.id,rules_version:r.version,weapon_id:w?.id})){setSelected("");setNotice("Attempt resolved. See your latest result below.");}else setOpen(false);}}>{busy?"Resolving…":"Attempt robbery"}</button></section>}
 {notice&&<p role="status">{notice}</p>}
 <section className="robbery-history"><h3>Your recent encounters</h3>{data.history.length?data.history.map(h=><article key={h.id}><div><strong>{h.attacking?"You targeted ":"Targeted by "}{h.other_name}</strong><time>{new Date(h.created_at).toLocaleString()}</time></div><p>{h.succeeded?(h.attacking?"Stole ":"Lost ")+"$"+h.cash.toLocaleString():"Defended · no cash taken"}{h.attacking?" · "+h.bullets+" bullets used":""}</p></article>):<p>No encounters this season.</p>}</section>
 </dialog>,document.body)}</>;
}
