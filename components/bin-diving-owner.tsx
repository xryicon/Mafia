"use client";
import {useState} from "react";
import Link from "next/link";
import {useBinDiving} from "@/components/use-bin-diving";
import {loot,emptyChance,type BinRules} from "@/lib/bin-diving";
function RulesForm({initial,busy,save}:{initial:BinRules;busy:boolean;save:(rules:BinRules,reason:string)=>Promise<boolean>}){
 const [rules,setRules]=useState(initial),[reason,setReason]=useState("");
 const total=rules.cash_chance+rules.pickaxe_chance+rules.pistol_blueprint_chance+rules.bullet_blueprint_chance;
 const number=(key:keyof BinRules,value:string)=>setRules(r=>({...r,[key]:Number(value)}));
 return <form className="bin-rules-form" onSubmit={async e=>{e.preventDefault();if(await save(rules,reason.trim()||"Updated city-wide bin diving rules"))setReason("");}}>
 <label className="bin-enabled"><input type="checkbox" checked={rules.enabled} onChange={e=>setRules(r=>({...r,enabled:e.target.checked}))}/> Open bin diving across the city</label>
 <div className="bin-rules-grid">{loot.map(l=><label key={l.id}>{l.name} chance (%)<input type="number" min="0" max="100" step="0.01" required value={rules[(l.id+"_chance") as keyof BinRules] as number} onChange={e=>number((l.id+"_chance") as keyof BinRules,e.target.value)}/></label>)}</div>
 <p className={total>100?"error":""}>{total>100?"The total cannot exceed 100%.":emptyChance(rules)+"% chance of finding nothing."} One result is rolled for each dive.</p>
 <div className="bin-rules-grid">{[["cooldown_seconds","Cooldown (seconds)",1,86400],["cash_min","Minimum cash find",1,1000000],["cash_max","Maximum cash find",rules.cash_min,1000000]].map(([key,label,min,max])=><label key={key}>{label}<input type="number" required min={min} max={max} step="1" value={rules[key as keyof BinRules] as number} onChange={e=>number(key as keyof BinRules,e.target.value)}/></label>)}</div>
 <label>Reason for this change (optional)<textarea minLength={5} maxLength={500} value={reason} onChange={e=>setReason(e.target.value)} placeholder="Describe the balance change for your audit history."/></label>
 <button className="bin-gold" disabled={busy||total>100||rules.cash_max<rules.cash_min}>Save bin diving rules →</button>
 <p className="bin-muted">Press Save to apply these percentages to every district and the player page. Changes affect future dives. Existing cooldowns and awarded loot stay as recorded. Pickaxe condition uses your existing mining setting. New open districts are included automatically.</p>
 </form>;
}
export function BinDivingOwner(){
 const h=useBinDiving(),data=h.data;
 return <section className="bin-panel bin-owner"><header><h2>Bin diving & loot</h2><Link href="/bin-diving">View the streets ↗</Link></header>
 {h.notice&&<p role={h.failed?"alert":"status"}>{h.notice}{h.retry&&<button disabled={h.working} onClick={()=>void h.retryAction()}>Retry safely</button>}</p>}
 {!data?<p>Loading city rules… <button onClick={h.refresh}>Refresh</button></p>:!data.can_manage?<p>Owner permission required.</p>:<><p>Control loot chances and the pace of searching across every open district.</p><RulesForm key={data.rules.version} initial={data.rules} busy={h.busy} save={(r,reason)=>h.act("configure",{...r,reason})}/><button className="bin-outline" disabled={h.busy} onClick={h.refresh}>Refresh current rules</button><p><Link href="/owner?section=adjustments">Give a player loot through Asset grants →</Link></p></>}
 </section>;
}
