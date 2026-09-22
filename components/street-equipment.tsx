"use client";
import Link from "next/link";
import {useEffect,useState} from "react";
import {createClient} from "@/lib/supabase/client";
import {equipmentSlots,type InventoryState} from "@/lib/inventory";
import {CommodityArtwork} from "./commodity-artwork";
import {GameIcon} from "./game-icon";

// Read the existing loadout. Inspecting a slot never changes equipment or consumes an item.
export function StreetEquipment({pause,revision}:{pause:()=>void;revision:string}){
 const [data,setData]=useState<InventoryState|null>(null),[selected,setSelected]=useState<string|null>(null),[error,setError]=useState(false);
 useEffect(()=>{let alive=true,request:AbortController|null=null;const refresh=async()=>{request?.abort();const current=new AbortController();request=current;try{const r=await createClient().rpc('inventory_state',{p_offset:0}).abortSignal(current.signal);if(!alive||current.signal.aborted)return;if(r.error||!r.data){setError(true);return;}setData(r.data);setError(false);}catch{if(alive&&!current.signal.aborted)setError(true);}};void refresh();const update=()=>{if(!document.hidden)void refresh();};window.addEventListener('blackwater:game',update);window.addEventListener('focus',update);return()=>{alive=false;request?.abort();window.removeEventListener('blackwater:game',update);window.removeEventListener('focus',update);};},[revision]);
 const gear=data?.gear.find(g=>g.location==='equipped'&&g.equipment_slot===selected),good=data?.goods.find(g=>g.id===gear?.good_id),label=equipmentSlots.find(([id])=>id===selected)?.[1];
 return <aside className="fp-equipment" aria-label="Street equipment">
 {selected&&<section className="fp-equipment-detail" aria-label="Selected equipment"><button className="fp-equipment-close" aria-label="Close equipment details" onClick={()=>setSelected(null)}>×</button><span className="eyebrow">{label}</span><h3>{good?.name??(data?'Empty slot':'Loading equipment…')}</h3>{gear&&<p>×{gear.quantity.toLocaleString()}{gear.condition!==null&&<> · Condition {gear.condition}</>}</p>}<p>{error?'Equipment could not refresh. Open Inventory to reconnect.':good?.description??'Manage your carried items and equipment in Inventory.'}</p><Link href="/inventory" onClick={pause}>Open Inventory →</Link></section>}
 <div className="fp-equipment-slots">{equipmentSlots.map(([id,label,icon])=>{const gear=data?.gear.find(g=>g.location==='equipped'&&g.equipment_slot===id),good=data?.goods.find(g=>g.id===gear?.good_id);return <button key={id} aria-label={label+(good?': '+good.name:data?', empty':', loading')} aria-pressed={selected===id} title={label+(good?': '+good.name:'')} onClick={()=>{pause();setSelected(selected===id?null:id);}}><span>{label.replace(' weapon','')}</span>{good?<CommodityArtwork goodId={good.id} size={44}/>:<GameIcon name={icon} size={25}/>}<small>{gear?gear.quantity>1?'×'+gear.quantity:gear.condition!==null?String(gear.condition):'Equipped':error?'?':data?'—':'…'}</small></button>;})}<Link href="/inventory" onClick={pause} aria-label="Open Inventory" title="Open Inventory"><GameIcon name="inventory" size={23}/><span>Inventory</span></Link></div>
 </aside>;
}
