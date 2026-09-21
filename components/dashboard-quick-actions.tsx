"use client";
import Link from "next/link";
import {useEffect,useState} from "react";
import {GameIcon} from "./game-icon";
const actions=[
 {id:"operations",label:"Plan an Operation",icon:"operations",dialog:"jobs"},
 {id:"range",label:"Shooting Range",icon:"target",href:"/shooting-range"},
 {id:"resources",label:"Explore Resources",icon:"pickaxe",href:"/districts/mines-and-quarries"},
 {id:"bins",label:"Bin Diving",icon:"bin",href:"/bin-diving"},
 {id:"refineries",label:"Refineries",icon:"production",href:"/refineries"},
 {id:"production",label:"Production",icon:"tools",dialog:"production"},
 {id:"jobs",label:"Find a Job",icon:"briefcase",dialog:"jobs"},
 {id:"inventory",label:"Inventory",icon:"inventory",href:"/inventory"},
 {id:"market",label:"Market",icon:"trade",href:"/market"},
 {id:"bank",label:"Bank",icon:"bank",href:"/bank"},
 {id:"gangs",label:"Gangs",icon:"people",href:"/gangs"},
 {id:"telegrams",label:"Telegrams",icon:"mail",href:"/telegrams"},
 {id:"skills",label:"Skills",icon:"respect",href:"/skills"},
 {id:"crafting",label:"Crafting",icon:"tools",href:"/crafting"},
] as const;
const defaults=actions.slice(0,7).map(a=>a.id as string);
export function DashboardQuickActions({playerId,onAction}:{playerId:string;onAction:(action:"jobs"|"production")=>void}){
 const key="blackwater:quick-actions:v1:"+playerId;
 const [selected,setSelected]=useState(defaults),[draft,setDraft]=useState(defaults),[editing,setEditing]=useState(false),[ready,setReady]=useState(false),[error,setError]=useState("");
 useEffect(()=>{setSelected(defaults);setEditing(false);setError("");try{const saved=JSON.parse(localStorage.getItem(key)||"null");if(Array.isArray(saved))setSelected([...new Set(saved.filter((id):id is string=>typeof id==="string"&&actions.some(a=>a.id===id)))]);}catch{setError("Saved shortcuts could not be loaded.");}setReady(true);},[key]);
 function save(){try{localStorage.setItem(key,JSON.stringify(draft));setSelected(draft);setEditing(false);setError("");}catch{setError("Your shortcuts could not be saved. Allow browser storage and try again.");}}
 function move(index:number,offset:number){const next=[...draft],to=index+offset;if(to<0||to>=next.length)return;[next[index],next[to]]=[next[to],next[index]];setDraft(next);}
 return <section className="command-quick" aria-label="Quick actions">
  <div className="quick-actions-heading"><h3>QUICK ACTIONS</h3>{!editing&&<button className="command-more" disabled={!ready} onClick={()=>{setDraft([...selected]);setError("");setEditing(true);}}>Customize</button>}</div>
  {error&&<p role="alert">{error}</p>}
  {editing?<div className="quick-actions-editor"><p>Choose your shortcuts and their order. Saved in this browser for your player.</p>
   <ol aria-label="Shortcut order">{draft.map((id,index)=>{const action=actions.find(a=>a.id===id)!;return <li key={id}><span>{action.label}</span><div><button aria-label={"Move "+action.label+" up"} disabled={index===0} onClick={()=>move(index,-1)}>↑</button><button aria-label={"Move "+action.label+" down"} disabled={index===draft.length-1} onClick={()=>move(index,1)}>↓</button></div></li>;})}</ol>
   <fieldset><legend>Show shortcuts</legend>{actions.map(action=><label key={action.id}><input type="checkbox" checked={draft.includes(action.id)} onChange={event=>setDraft(event.target.checked?[...draft,action.id]:draft.filter(id=>id!==action.id))}/>{action.label}</label>)}</fieldset>
   <button className="command-more" onClick={()=>setDraft([...defaults])}>Reset to default</button>
   <div className="quick-actions-save"><button className="command-button" onClick={save}>Save shortcuts</button><button className="command-button" onClick={()=>{setEditing(false);setError("");}}>Cancel</button></div>
  </div>:<>{selected.map(id=>{const action=actions.find(a=>a.id===id)!;const content=<><GameIcon name={action.icon}/><span>{action.label}</span><GameIcon name="arrow" size={16}/></>;return "href" in action?<Link key={id} className="command-button" href={action.href}>{content}</Link>:<button key={id} className="command-button" onClick={()=>onAction(action.dialog)}>{content}</button>;})}{!selected.length&&<p>No shortcuts selected. Use Customize to add some.</p>}</>}
 </section>;
}
