"use client";
import {useEffect,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase/client";
import type {CraftState,CraftRecipe} from "@/lib/crafting";
export function CraftingOwner(){
 const [data,setData]=useState<CraftState|null>(null),[id,setId]=useState(""),[notice,setNotice]=useState(""),[busy,setBusy]=useState(false);
 const refresh=async()=>{const r=await createClient().rpc("crafting_state");if(r.error||!r.data)throw new Error("Recipe controls could not load.");setData(r.data);};
 useEffect(()=>{void refresh().catch(e=>setNotice(e.message));},[]);
 if(!data)return <p>{notice||"Loading recipe controls…"}</p>;if(!data.can_manage)return <p>Crafting management permission required.</p>;
 const recipe=data.recipes.find(r=>r.id===id)??data.recipes[0];
 const save=async(p:Record<string,unknown>)=>{setBusy(true);setNotice("");try{const r=await createClient().rpc("crafting_manage",{p_payload:p});if(r.error||r.data?.error)throw new Error(r.data?.error||"Recipe could not be saved.");setNotice(r.data.message);await refresh();}catch(e){setNotice(e instanceof Error?e.message:"Save failed.");}finally{setBusy(false);}};
 return <section className="cf-page cf-owner"><h2>Crafting & blueprints</h2><p>Configure material costs, output, duration and availability. Learned recipes reset each season. Queued jobs retain their original requirements and output.</p><p>Queue limits are in <Link href="/owner?section=economy">economy settings</Link>. Item weights and equipment slots are in <Link href="/owner?section=inventory">inventory settings</Link>.</p>{notice&&<p role="status" className="cf-notice">{notice}</p>}<div className="cf-owner-header"><label>Recipe<select aria-label="Edit crafting recipe" value={recipe?.id??""} onChange={e=>setId(e.target.value)}>{data.recipes.map(r=><option key={r.id} value={r.id}>{r.name}</option>)}</select></label></div>{recipe&&<RecipeForm key={recipe.id+":"+recipe.version} recipe={recipe} data={data} save={save} busy={busy}/>}</section>;
}
function RecipeForm({recipe:r,data,save,busy}:{recipe:CraftRecipe;data:CraftState;save:(p:Record<string,unknown>)=>Promise<void>;busy:boolean}){
 const [rows,setRows]=useState(Object.entries(r.materials).map(([good,quantity])=>({good,quantity:String(quantity)})));
 const goods=data.inventory.goods.filter(g=>g.id!==r.output_good_id&&g.id!==r.blueprint_good_id);
 return <form className="cf-panel" onSubmit={e=>{e.preventDefault();const v=new FormData(e.currentTarget);void save({id:r.id,version:r.version,name:v.get("name"),description:v.get("description"),seconds:Number(v.get("seconds")),output_units:Number(v.get("output_units")),enabled:v.get("enabled")==="on",materials:Object.fromEntries(rows.map(x=>[x.good,Number(x.quantity)])),reason:v.get("reason")});}}>
 <label>Recipe name<input name="name" defaultValue={r.name} minLength={2} maxLength={80} required disabled={busy}/></label><label>Description<textarea name="description" defaultValue={r.description} maxLength={600} disabled={busy}/></label>
 <label>Craft time per batch (seconds)<input name="seconds" type="number" min={1} max={604800} defaultValue={r.seconds} required disabled={busy}/></label><label>Output units per batch<input name="output_units" type="number" min={1} max={10000} defaultValue={r.output_units} required disabled={busy}/></label>
 <label><span><input name="enabled" type="checkbox" defaultChecked={r.enabled} disabled={busy} style={{width:20,minHeight:20}}/> Recipe available</span></label><h3>Materials per batch</h3>{rows.map((x,i)=><div className="cf-material-edit" key={i}><select aria-label={"Material "+(i+1)} value={x.good} disabled={busy} onChange={e=>setRows(rows.map((x,j)=>j===i?{...x,good:e.target.value}:x))}>{goods.filter(g=>g.id===x.good||!rows.some(row=>row.good===g.id)).map(g=><option key={g.id} value={g.id}>{g.name}</option>)}</select><input aria-label={"Material "+(i+1)+" quantity"} type="number" min={1} max={10000} value={x.quantity} required disabled={busy} onChange={e=>setRows(rows.map((x,j)=>j===i?{...x,quantity:e.target.value}:x))}/><button type="button" className="cf-outline" aria-label={"Remove material "+(i+1)} disabled={busy||rows.length===1} onClick={()=>setRows(rows.filter((_,j)=>j!==i))}>×</button></div>)}
 <button type="button" className="cf-outline" disabled={busy||rows.length>=12||!goods.some(g=>!rows.some(x=>x.good===g.id))} onClick={()=>{const g=goods.find(g=>!rows.some(x=>x.good===g.id));if(g)setRows([...rows,{good:g.id,quantity:"1"}]);}}>Add material</button>
 <label>Recipe audit reason<input name="reason" minLength={5} maxLength={500} required disabled={busy}/></label><button className="cf-gold" disabled={busy}>Save crafting recipe</button></form>;
}
