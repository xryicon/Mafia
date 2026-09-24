"use client";
import {useState} from "react";
import Link from "next/link";
import {useBinDiving} from "@/components/use-bin-diving";
import {loot,emptyChance,type BinRules} from "@/lib/bin-diving";
function VehicleForm({model,busy,save}:{model:import("@/lib/street-operations").VehicleModel;busy:boolean;save:(p:Record<string,unknown>)=>Promise<boolean>}){
 const [price,setPrice]=useState(String(model.sale_value)),[enabled,setEnabled]=useState(model.enabled),[reason,setReason]=useState("");
 return <form className="bin-rules-form" onSubmit={async e=>{e.preventDefault();if(await save({id:model.id,version:model.version,sale_value:Number(price),enabled,reason}))setReason("");}}><h3>{model.name}</h3><div className="bin-rules-grid"><label>Resale price ($)<input type="number" required min="1" max="100000000" step="1" value={price} onChange={e=>setPrice(e.target.value)}/></label><label className="bin-enabled"><input type="checkbox" checked={enabled} onChange={e=>setEnabled(e.target.checked)}/> Available on the streets</label></div><label>Reason<input required minLength={5} maxLength={500} value={reason} onChange={e=>setReason(e.target.value)}/></label><button className="bin-gold" disabled={busy}>Save {model.name}</button></form>;
}
function RulesForm({initial,busy,save}:{initial:BinRules;busy:boolean;save:(rules:BinRules,reason:string)=>Promise<boolean>}){
 const [rules,setRules]=useState(initial),[reason,setReason]=useState("");
 const total=rules.cash_chance+rules.pickaxe_chance+rules.lockpick_chance+rules.pistol_blueprint_chance+rules.bullet_blueprint_chance+rules.bandages_blueprint_chance+(rules.reinforced_jacket_blueprint_chance??0)+(rules.kevlar_vest_blueprint_chance??0);
 const number=(key:keyof BinRules,value:string)=>setRules(r=>({...r,[key]:Number(value)}));
 return <form className="bin-rules-form" onSubmit={async e=>{e.preventDefault();if(await save(rules,reason.trim()||"Updated city-wide bin diving rules"))setReason("");}}>
 <label className="bin-enabled"><input type="checkbox" checked={rules.enabled} onChange={e=>setRules(r=>({...r,enabled:e.target.checked}))}/> Open bin diving across the city</label>
 <div className="bin-rules-grid">{loot.map(l=><label key={l.id}>{l.name} chance (%)<input type="number" min="0" max="100" step="0.01" required value={(rules[(l.id+"_chance") as keyof BinRules] as number)??0} onChange={e=>number((l.id+"_chance") as keyof BinRules,e.target.value)}/></label>)}</div>
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
 {!data?<p>Loading city rules… <button onClick={h.refresh}>Refresh</button></p>:!data.can_manage?<p>Owner permission required.</p>:<><p>Control scavenging loot across every open district. Bins and successfully opened cars use these chances. Each car attempt consumes one lockpick.</p><p><Link href="/owner?section=economy">Edit island risk, police combat, vehicle bays, events, healing and movement rules in Economy settings →</Link></p><RulesForm key={data.rules.version} initial={data.rules} busy={h.busy} save={(r,reason)=>h.act("configure",{...r,reason})}/><h3>Street vehicles</h3><p>Prices apply to future theft attempts. Existing vehicles keep their recorded resale value.</p>{data.scavenging?.operations?.models.map(m=><VehicleForm key={m.id+"-"+m.version} model={m} busy={h.busy} save={p=>h.act("scav_vehicle_model",p)}/>)}<button className="bin-outline" disabled={h.busy} onClick={h.refresh}>Refresh current rules</button><p><Link href="/owner?section=adjustments">Give a player loot through Asset grants →</Link></p></>}
 </section>;
}
