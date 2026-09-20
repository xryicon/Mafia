"use client";
import {useEffect,useState} from "react";
import {GameIcon} from "./game-icon";
import {streetPoint,walkingPosition,type ScavengingState} from "@/lib/scavenging";
import {binCountdown} from "@/lib/bin-diving";
import "./scavenging.css";

type Props={state?:ScavengingState;district:{id:string;name:string;image_url:string}|undefined;now:number;busy:boolean;blocked:boolean;cooldown:number;lockpicks:number;act:(action:string,payload?:Record<string,unknown>)=>Promise<boolean>};
export function ScavengingMap({state,district,now,busy,blocked,cooldown,lockpicks,act}:Props){
 const [selected,setSelected]=useState<string|null>(null),[frame,setFrame]=useState(now),[zoom,setZoom]=useState(1);
 const session=state?.session;
 useEffect(()=>{const start=performance.now();let id:number;const tick=()=>{setFrame(now+performance.now()-start);id=requestAnimationFrame(tick);};id=requestAnimationFrame(tick);return()=>cancelAnimationFrame(id);},[now]);
 useEffect(()=>{setSelected(null);setZoom(1);},[district?.id]);
 const entered=!!session&&session.district_id===district?.id;
 const moving=entered&&Date.parse(session.arrives_at)>frame;
 const pending=entered?session.pending:null;
 const target=entered?state?.targets.find(t=>t.id===selected):undefined;
 const atTarget=!!target&&entered&&session.node===target.node&&!moving;
 const searched=target?.ready_at?Date.parse(target.ready_at)>frame:false;
 const remaining=pending?Math.max(0,Math.ceil((Date.parse(pending.ready_at)-frame)/1000)):0;
 const point=entered?walkingPosition(session,frame):streetPoint(0);
 const travel=(node:number)=>{if(!entered||busy||blocked||moving||pending)return;void act("scav_move",{node});};
 const choose=(id:string)=>{setSelected(id);const site=state?.targets.find(t=>t.id===id);if(site)travel(site.node);};
 const streets=[0,1,2].map((n)=>state?.streets[n]??[`${district?.name??"District"} Road`,"Lantern Street","Foundry Lane"][n]);
 return <div className="scav-workspace">
 <div className="scav-map-toolbar"><span><i className="scav-dot-key"/> You <span className="scav-key">▣ Bin · ▰ Parked car</span></span><div><button aria-label="Zoom out" disabled={zoom===1} onClick={()=>setZoom(z=>Math.max(1,z-.25))}>−</button><button aria-label="Zoom in" disabled={zoom===2} onClick={()=>setZoom(z=>Math.min(2,z+.25))}>+</button></div></div>
 {!entered?<div className="scav-entry" style={{backgroundImage:`linear-gradient(90deg,#071316e8,#07131666),url(${district?.image_url||"/art/bin-diving.png"})`}}><p className="eyebrow">BLACKWATER / STREET OPERATIONS</p><h2>The city rewards<br/>a curious mind.</h2><p>Walk the streets. Search forgotten bins. Try the locks on parked cars. Every find feeds your next move.</p><button className="bin-gold" disabled={busy||blocked||!district} onClick={()=>void act("scav_enter",{district_id:district?.id})}>Enter {district?.name??"district"} <GameIcon name="arrow"/></button></div>:<>
 <div className="scav-map-scroll" tabIndex={0} aria-label="Street map; scroll to pan when zoomed">
 <svg className="scav-map" viewBox="0 0 1000 680" style={{width:`${zoom*100}%`}} role="group" aria-label={district?.name+" scavenging street map"} onClick={event=>{if(event.target!==event.currentTarget)return;const box=event.currentTarget.getBoundingClientRect();const x=(event.clientX-box.left)/box.width*1000,y=(event.clientY-box.top)/box.height*680;travel(Math.max(0,Math.min(2,Math.round((y-130)/210)))*5+Math.max(0,Math.min(4,Math.round((x-100)/200))));}}>
 <defs><pattern id="scav-grain" width="12" height="12" patternUnits="userSpaceOnUse"><path d="M0 12L12 0" stroke="#304039" strokeWidth=".5"/></pattern><radialGradient id="scav-lamp"><stop stopColor="#d7ad68" stopOpacity=".3"/><stop offset="1" stopColor="#d7ad68" stopOpacity="0"/></radialGradient></defs>
 <rect width="1000" height="680" fill="#101d20" pointerEvents="none"/><rect width="1000" height="680" fill="url(#scav-grain)" pointerEvents="none"/>
 {Array.from({length:8},(_,i)=>{const x=137+(i%4)*200,y=163+Math.floor(i/4)*210;return <g key={i} pointerEvents="none"><rect x={x} y={y} width="127" height="142" rx="3" fill="#17252a" stroke="#435048"/><rect x={x+9} y={y+8} width="109" height="125" fill="#1e2d2f" stroke="#354340"/>{Array.from({length:8},(_,w)=><rect key={w} x={x+18+(w%4)*25} y={y+22+Math.floor(w/4)*79} width="9" height="13" fill={w%3?"#847043":"#263d3d"}/>)}<text x={x+64} y={y+76} textAnchor="middle" fill="#8b9284" fontSize="12">BLOCK {String(i+1).padStart(2,"0")}</text></g>;})}
 {[130,340,550].map((y,i)=><g key={y}><path d={`M45 ${y}H955`} stroke="#344242" strokeWidth="48"/><path d={`M45 ${y}H955`} stroke="#bc995a" strokeOpacity=".25" strokeDasharray="8 15"/><text x="500" y={y-38} textAnchor="middle" fill="#d0ba8f" fontSize="16" letterSpacing="2">{streets[i]}</text></g>)}
 {[100,300,500,700,900].map(x=><g key={x}><path d={`M${x} 72V608`} stroke="#344242" strokeWidth="42"/><path d={`M${x} 78V602`} stroke="#b69a61" strokeOpacity=".2" strokeDasharray="8 15"/></g>)}
 <text x="44" y="40" fill="#d8c297" fontFamily="Georgia" fontSize="22">{district?.name.toUpperCase()}</text><text x="955" y="640" fill="#9da596" textAnchor="end" fontSize="13">N ↑ · CLICK TO WALK</text>
 {Array.from({length:15},(_,node)=>{const p=streetPoint(node);return <g key={node} role="button" tabIndex={0} aria-label={`Walk to ${streets[Math.floor(node/5)]}, block ${node%5+1}`} onClick={()=>travel(node)} onKeyDown={e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();travel(node);}}}><circle cx={p.x} cy={p.y} r="35" fill="transparent"/><circle cx={p.x-22} cy={p.y-23} r="33" fill="url(#scav-lamp)" pointerEvents="none"/><circle cx={p.x-22} cy={p.y-23} r="3" fill="#c9a065" pointerEvents="none"/></g>;})}
 {session.path.length>1&&moving&&<polyline points={session.path.map(n=>{const p=streetPoint(n);return `${p.x},${p.y}`;}).join(" ")} fill="none" stroke="#d8b777" strokeWidth="3" strokeDasharray="5 8" pointerEvents="none"/>}
 {state?.targets.map((site,index)=>{const p=streetPoint(site.node),empty=site.ready_at&&Date.parse(site.ready_at)>frame;return <g className={"scav-target "+(selected===site.id?"selected ":"")+(empty?"searched":"")} key={site.id} role="button" tabIndex={0} aria-label={`${site.kind==="bin"?"Bin":"Car"} ${index+1} on ${streets[Math.floor(site.node/5)]}${empty?", searched":""}`} onClick={()=>choose(site.id)} onKeyDown={e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();choose(site.id);}}}><rect x={p.x-24} y={p.y-24} width="48" height="48" rx="7"/>{site.kind==="bin"?<path d={`M${p.x-10} ${p.y-8}h20l-2 23h-16z M${p.x-13} ${p.y-11}h26 M${p.x-5} ${p.y-16}h10`}/>:<path d={`M${p.x-16} ${p.y-6}l5-9h22l5 9v19h-32z M${p.x-16} ${p.y-2}h32 M${p.x-9} ${p.y+7}h3 M${p.x+6} ${p.y+7}h3`}/>}<text x={p.x+31} y={p.y+5} fontSize="13">{index+1}</text></g>;})}
 <g pointerEvents="none" aria-label="Your position"><circle cx={point.x} cy={point.y} r="19" fill="#81b49a" opacity=".18"/><circle cx={point.x} cy={point.y} r="8" fill="#9ed1ad" stroke="#edf6d8" strokeWidth="2"/><text x={point.x} y={point.y+34} textAnchor="middle" fill="#eddfb7" fontSize="13">YOU</text></g>
 </svg></div>
 <div className="scav-action-desk"><div><p className="eyebrow">{pending?"ACTION IN PROGRESS":moving?"ON FOOT":"STREET INTELLIGENCE"}</p><h3>{pending?pending.kind==="car"?"Working the lock":"Searching the bin":target?target.kind==="car"?"Parked car":"Street bin":"Choose your next stop"}</h3><p>{pending?remaining?`Ready in ${binCountdown(remaining)}`:"Your search is ready to collect.":moving?"Follow the marked route. You can search when you arrive.":target?.kind==="car"?`One lockpick per attempt · ${state?.settings.scavenging_car_success_percent}% opening chance · +${state?.settings.scavenging_lock_xp} XP when opened. Uses the loot chances below.`:target?"Search for cash, tools or blueprints. One find per search.":"Click a bin, car, or street crossing. Your marker walks there."}</p></div>
 <div className="scav-desk-actions">{pending?<><button className="bin-gold" disabled={busy||blocked||remaining>0} onClick={()=>void act("scav_finish",{attempt_id:pending.id})}>{remaining?`Searching · ${binCountdown(remaining)}`:"Collect search"}</button><button className="bin-outline" disabled={busy} onClick={()=>void act("scav_cancel")}>Abandon search</button></>:<button className="bin-gold" disabled={busy||blocked||!atTarget||searched||cooldown>0||(target?.kind==="car"&&!lockpicks)} onClick={()=>void act("scav_search",{target_id:target?.id})}>{moving?"Walking…":cooldown?"Next search in "+binCountdown(cooldown):searched?"Already searched":!target?"Select a location":target.kind==="car"?lockpicks?"Lockpick car":"Lockpick required":"Search the bins"}</button>}<small>{lockpicks} lockpicks carried</small></div></div>
 <div className="scav-location-list" aria-label="Nearby search locations">{state?.targets.map((site,i)=><button key={site.id} aria-pressed={selected===site.id} onClick={()=>choose(site.id)}>{site.kind==="bin"?"Bin":"Car"} {i+1}<span>{streets[Math.floor(site.node/5)]}</span></button>)}</div>
 </>}
 </div>;
}
