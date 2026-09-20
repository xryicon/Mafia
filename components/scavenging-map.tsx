"use client";
import {useEffect,useState,useRef} from "react";
import {GameIcon} from "./game-icon";
import {streetPoint,walkingPosition,nearestStreetNode,STREET_ROWS,type ScavengingState} from "@/lib/scavenging";
import {binCountdown} from "@/lib/bin-diving";
import "./scavenging.css";
import "./scavenging-map-art.css";

type Props={state?:ScavengingState;district:{id:string;name:string;image_url:string}|undefined;now:number;busy:boolean;blocked:boolean;cooldown:number;lockpicks:number;act:(action:string,payload?:Record<string,unknown>)=>Promise<boolean>};
export function ScavengingMap({state,district,now,busy,blocked,cooldown,lockpicks,act}:Props){
 const [selected,setSelected]=useState<string|null>(null),[queued,setQueued]=useState<number|null>(null),[frame,setFrame]=useState(now),[zoom,setZoom]=useState(1);
 const session=state?.session;
 const workspace=useRef<HTMLDivElement>(null),mapViewport=useRef<HTMLDivElement>(null);
 const [fit,setFit]=useState({width:640,height:440,header:76});
 useEffect(()=>{const start=performance.now();let id:number;const tick=()=>{setFrame(now+performance.now()-start);id=requestAnimationFrame(tick);};id=requestAnimationFrame(tick);return()=>cancelAnimationFrame(id);},[now]);
 useEffect(()=>{setSelected(null);setQueued(null);setZoom(1);},[district?.id]);
 const entered=!!session&&session.district_id===district?.id;
 useEffect(()=>{
  if(!entered||!workspace.current||!mapViewport.current)return;
  const root=workspace.current,viewport=mapViewport.current,header=document.querySelector('.estate-header'),toolbar=root.querySelector('.scav-map-toolbar'),desk=root.querySelector('.scav-action-desk');
  const resize=()=>{const headerHeight=header?.getBoundingClientRect().height??76;const available=Math.max(120,window.innerHeight-headerHeight-(toolbar?.getBoundingClientRect().height??70)-(desk?.getBoundingClientRect().height??180)-24);const width=Math.min(viewport.clientWidth,available*1000/680);setFit(old=>old.width===width&&old.height===available&&old.header===headerHeight?old:{width,height:available,header:headerHeight});};
  const observer=new ResizeObserver(resize);for(const element of [viewport,header,toolbar,desk])if(element)observer.observe(element);
  resize();const frame=requestAnimationFrame(()=>root.scrollIntoView({block:'start',behavior:'instant'}));window.addEventListener('resize',resize);
  return()=>{observer.disconnect();cancelAnimationFrame(frame);window.removeEventListener('resize',resize);};
 },[entered,district?.id]);
 const moving=entered&&Date.parse(session.arrives_at)>frame;
 const pending=entered?session.pending:null;
 const target=entered?state?.targets.find(t=>t.id===selected):undefined;
 const atTarget=!!target&&entered&&session.node===target.node&&!moving;
 const searched=target?.ready_at?Date.parse(target.ready_at)>frame:false;
 const remaining=pending?Math.max(0,Math.ceil((Date.parse(pending.ready_at)-frame)/1000)):0;
 const point=entered?walkingPosition(session,frame):streetPoint(0);
 const travel=(node:number)=>{if(!entered||blocked||pending)return;setSelected(null);setQueued(node);};
 const choose=(id:string)=>{const site=state?.targets.find(t=>t.id===id);if(site)travel(site.node);setSelected(id);};
 useEffect(()=>{if(queued===null||!entered||busy||blocked||moving||pending)return;setQueued(null);if(queued!==session.node)void act("scav_move",{node:queued});},[queued,entered,busy,blocked,moving,pending,session?.node,act]);
 const streets=[0,1,2].map((n)=>state?.streets[n]??[`${district?.name??"District"} Road`,"Lantern Street","Foundry Lane"][n]);
 return <div ref={workspace} className="scav-workspace" style={{scrollMarginTop:fit.header+8}}>
 <div className="scav-map-toolbar"><span><i className="scav-dot-key"/> You <span className="scav-key">▣ Bin · ▰ Parked car</span></span><div><button aria-label="Zoom out" disabled={zoom===1} onClick={()=>setZoom(z=>Math.max(1,z-.25))}>−</button><button aria-label="Zoom in" disabled={zoom===2} onClick={()=>setZoom(z=>Math.min(2,z+.25))}>+</button></div></div>
 {!entered?<div className="scav-entry" style={{backgroundImage:`linear-gradient(90deg,#071316e8,#07131666),url(${district?.image_url||"/art/bin-diving.png"})`}}><p className="eyebrow">BLACKWATER / STREET OPERATIONS</p><h2>The city rewards<br/>a curious mind.</h2><p>Walk the streets. Search forgotten bins. Try the locks on parked cars. Every find feeds your next move.</p><button className="bin-gold" disabled={busy||blocked||!district} onClick={()=>void act("scav_enter",{district_id:district?.id})}>Enter {district?.name??"district"} <GameIcon name="arrow"/></button></div>:<>
 <div ref={mapViewport} className="scav-map-scroll scav-map-fitted" style={{height:fit.height}} tabIndex={0} aria-label="Street map; scroll to pan when zoomed">
 <svg className="scav-map" viewBox="0 0 1000 680" style={{width:fit.width*zoom}} role="group" aria-label={district?.name+" scavenging street map"} onClick={event=>{if(event.target!==event.currentTarget)return;const box=event.currentTarget.getBoundingClientRect();const x=(event.clientX-box.left)/box.width*1000,y=(event.clientY-box.top)/box.height*680;travel(nearestStreetNode(x,y));}}>
 <defs><linearGradient id="scav-map-shade" x2="0" y2="1"><stop stopColor="#051114" stopOpacity=".25"/><stop offset=".45" stopColor="#051114" stopOpacity="0"/><stop offset="1" stopColor="#051114" stopOpacity=".15"/></linearGradient></defs>
 <image className="scav-map-art" href="/art/scavenging/blackwater-streets.webp" x="0" y="0" width="1000" height="680" preserveAspectRatio="none" pointerEvents="none"/><rect width="1000" height="680" fill="url(#scav-map-shade)" pointerEvents="none"/>



 {STREET_ROWS.map((y,i)=><g key={y} className="scav-street-label" pointerEvents="none"><rect x="285" y={y-54} width="230" height="32" rx="3"/><text x="400" y={y-32} textAnchor="middle" fontSize="18" letterSpacing="1.5">{streets[i]}</text></g>)}
 <g className="scav-map-title" pointerEvents="none"><rect x="24" y="14" width="370" height="52" rx="3"/><text x="42" y="47" fontFamily="Georgia" fontSize="22">{district?.name.toUpperCase()}</text></g><text className="scav-compass" x="962" y="652" textAnchor="end" fontSize="17" pointerEvents="none">N ↑</text>
 {Array.from({length:15},(_,node)=>{const p=streetPoint(node);return <g key={node} role="button" tabIndex={0} aria-label={`Walk to ${streets[Math.floor(node/5)]}, block ${node%5+1}`} onClick={()=>travel(node)} onKeyDown={e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();travel(node);}}}><circle cx={p.x} cy={p.y} r="35" fill="transparent"/></g>;})}
 {session.path.length>1&&moving&&<polyline points={session.path.map(n=>{const p=streetPoint(n);return `${p.x},${p.y}`;}).join(" ")} fill="none" stroke="#d8b777" strokeWidth="3" strokeDasharray="5 8" pointerEvents="none"/>}
 {state?.targets.map((site,index)=>{const road=streetPoint(site.node),p={x:road.x+24,y:road.y+20},empty=site.ready_at&&Date.parse(site.ready_at)>frame;return <g className={"scav-target "+(selected===site.id?"selected ":"")+(empty?"searched":"")} key={site.id} role="button" tabIndex={0} aria-label={`${site.kind==="bin"?"Bin":"Car"} ${index+1} on ${streets[Math.floor(site.node/5)]}${empty?", searched":""}`} onClick={()=>choose(site.id)} onKeyDown={e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();choose(site.id);}}}><rect x={p.x-24} y={p.y-24} width="48" height="48" rx="7"/>{site.kind==="bin"?<path d={`M${p.x-10} ${p.y-8}h20l-2 23h-16z M${p.x-13} ${p.y-11}h26 M${p.x-5} ${p.y-16}h10`}/>:<path d={`M${p.x-16} ${p.y-6}l5-9h22l5 9v19h-32z M${p.x-16} ${p.y-2}h32 M${p.x-9} ${p.y+7}h3 M${p.x+6} ${p.y+7}h3`}/>}<text x={p.x+31} y={p.y+5} fontSize="13">{index+1}</text></g>;})}
 <g pointerEvents="none" aria-label="Your position"><circle cx={point.x} cy={point.y} r="19" fill="#81b49a" opacity=".18"/><circle cx={point.x} cy={point.y} r="8" fill="#9ed1ad" stroke="#edf6d8" strokeWidth="2"/><text x={point.x} y={point.y+34} textAnchor="middle" fill="#eddfb7" fontSize="13">YOU</text></g>
 </svg></div>
 <div className="scav-action-desk"><div><p className="eyebrow">{pending?"ACTION IN PROGRESS":moving?"ON FOOT":"STREET INTELLIGENCE"}</p><h3>{pending?pending.kind==="car"?"Working the lock":"Searching the bin":target?target.kind==="car"?"Parked car":"Street bin":"Choose your next stop"}</h3><p>{pending?remaining?`Ready in ${binCountdown(remaining)}`:"Your search is ready to collect.":moving?"Follow the marked route. You can search when you arrive.":target?.kind==="car"?`One lockpick per attempt · ${state?.settings.scavenging_car_success_percent}% opening chance · +${state?.settings.scavenging_lock_xp} XP when opened. Uses the loot chances below.`:target?"Search for cash, tools or blueprints. One find per search.":"Click a bin, car, or street crossing. Your marker walks there."}</p></div>
 <div className="scav-desk-actions">{pending?<><button className="bin-gold" disabled={busy||blocked||remaining>0} onClick={()=>void act("scav_finish",{attempt_id:pending.id})}>{remaining?`Searching · ${binCountdown(remaining)}`:"Collect search"}</button><button className="bin-outline" disabled={busy} onClick={()=>void act("scav_cancel")}>Abandon search</button></>:<button className="bin-gold" disabled={busy||blocked||!atTarget||searched||cooldown>0||(target?.kind==="car"&&!lockpicks)} onClick={()=>void act("scav_search",{target_id:target?.id})}>{moving?"Walking…":cooldown?"Next search in "+binCountdown(cooldown):searched?"Already searched":!target?"Select a location":target.kind==="car"?lockpicks?"Lockpick car":"Lockpick required":"Search the bins"}</button>}<small>{lockpicks} lockpicks carried</small></div></div>
 <div className="scav-location-list" aria-label="Nearby search locations">{state?.targets.map((site,i)=><button key={site.id} aria-pressed={selected===site.id} onClick={()=>choose(site.id)}>{site.kind==="bin"?"Bin":"Car"} {i+1}<span>{streets[Math.floor(site.node/5)]}</span></button>)}</div>
 </>}
 </div>;
}
