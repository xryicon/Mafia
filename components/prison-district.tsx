"use client";
import Link from "next/link";
import {useCallback,useEffect,useRef,useState,type PointerEvent} from "react";
import {createClient} from "@/lib/supabase/client";
import {attemptCountdown,sentenceCountdown,type PrisonBreakAttempt,type PrisonState} from "@/lib/prison";
import {GameIcon} from "./game-icon";

type BreakResult={message?:string;error?:string;outcome?:"started"|"continue"|"success"|"caught"|"cancelled";turn?:number;attempts_left?:number;reward_power?:number;attempt?:PrisonBreakAttempt};

function LockGame({attempt,now,busy,angle,turn,onAngle,onTension}:{attempt:PrisonBreakAttempt;now:number;busy:boolean;angle:number;turn:number;onAngle:(angle:number)=>void;onTension:()=>void}){
 const lock=useRef<SVGSVGElement>(null);
 const point=(event:PointerEvent<SVGSVGElement>)=>{const rect=lock.current?.getBoundingClientRect();if(!rect)return;onAngle(Math.max(-80,Math.min(80,Math.round(((event.clientX-rect.left)/rect.width)*160-80))));};
 return <div className="prison-lock-game">
  <div className="prison-lock-head"><div><p className="eyebrow">ACTIVE EXTRACTION</p><h2>{attempt.inmate_handle}</h2></div><span className="prison-game-clock"><GameIcon name="clock" size={16}/>{attemptCountdown(attempt.expires_at,now)}</span></div>
  <div className="prison-lock-instructions"><span>MOVE THE PICK</span><i/><span>APPLY TENSION</span><i/><span>OPEN THE LOCK</span></div>
  <svg ref={lock} className="prison-lock" viewBox="0 0 520 370" role="img" aria-label={`Prison lock with lockpick at ${angle} degrees`} onPointerDown={event=>{event.currentTarget.setPointerCapture(event.pointerId);point(event);}} onPointerMove={event=>{if(event.currentTarget.hasPointerCapture(event.pointerId))point(event);}} onPointerUp={event=>event.currentTarget.releasePointerCapture(event.pointerId)}>
   <defs><radialGradient id="lock-face"><stop stopColor="#85908a"/><stop offset=".42" stopColor="#3f4a47"/><stop offset="1" stopColor="#151f20"/></radialGradient><linearGradient id="lock-body" x2="0" y2="1"><stop stopColor="#43504d"/><stop offset="1" stopColor="#111b1e"/></linearGradient></defs>
   <path className="prison-shackle" d="M174 139V94c0-111 172-111 172 0v45"/>
   <rect className="prison-lock-body" x="101" y="116" width="318" height="224" rx="20" fill="url(#lock-body)"/>
   <g className="prison-pin-bank">{[0,1,2,3,4].map((pin)=><g key={pin} transform={`translate(${181+pin*40} 0)`}><rect x="0" y="132" width="19" height="68" rx="5"/><line x1="9.5" y1="132" x2="9.5" y2={151+((pin*13)%24)}/></g>)}</g>
   <g className="prison-cylinder" style={{transform:`rotate(${turn*.34}deg)`}}>
    <circle cx="260" cy="242" r="91" fill="url(#lock-face)"/><circle cx="260" cy="242" r="70"/>
    <path className="prison-keyway" d="M248 213c0-17 24-17 24 0 0 9-5 13-8 18l13 54h-34l13-54c-3-5-8-9-8-18z"/>
    <circle cx="260" cy="242" r="84" className="prison-lock-ticks"/>
   </g>
   <g className="prison-pick" style={{transform:`rotate(${angle}deg)`}}><path d="M258 244L450 244l26-15"/><path d="M405 237h70l20 14-18 13h-72z"/></g>
   <g className="prison-tension"><path d="M256 254l-18 73h-82"/><path d="M159 318h-45v18h45z"/></g>
   <text x="260" y="326" textAnchor="middle">BLACKWATER MUNICIPAL · CELL BLOCK A</text>
  </svg>
  <label className="prison-angle">Lockpick angle <strong>{angle>0?"+":""}{angle}°</strong><input aria-label="Lockpick angle" type="range" min="-80" max="80" value={angle} onChange={event=>onAngle(Number(event.target.value))}/></label>
  <div className="prison-tension-meter"><span>CYLINDER TURN</span><div><i style={{width:`${turn}%`}}/></div><strong>{turn}° / 90°</strong></div>
  <button className="command-button prison-tension-button" disabled={busy} onClick={onTension}><GameIcon name="lock"/><span>{busy?"Testing the pins…":"Apply tension"}</span><GameIcon name="arrow" size={16}/></button>
  <p className="prison-attempts"><b>{attempt.attempts_left}</b> tension {attempt.attempts_left===1?"attempt":"attempts"} left · More cylinder movement means the pick is closer.</p>
 </div>;
}

export function PrisonDistrict({initial}:{initial:PrisonState}) {
 const [data,setData]=useState(initial),[now,setNow]=useState(Date.parse(initial.server_time)),[error,setError]=useState(""),[notice,setNotice]=useState(""),[busy,setBusy]=useState(false),[angle,setAngle]=useState(0),[turn,setTurn]=useState(initial.attempt?.last_turn??0),[result,setResult]=useState<BreakResult|null>(null);
 const offset=useRef(Date.parse(initial.server_time)-Date.now()),loading=useRef(false),alive=useRef(true),resetTimer=useRef<ReturnType<typeof setTimeout>|null>(null);
 const refresh=useCallback(async()=>{
  if(loading.current)return;loading.current=true;
  try{const response=await createClient().rpc("prison_state");if(response.error||!response.data)throw new Error();
   if(alive.current){offset.current=Date.parse(response.data.server_time)-Date.now();setNow(Date.parse(response.data.server_time));setData(response.data);setError("");window.dispatchEvent(new CustomEvent("blackwater:custody",{detail:response.data}));}
  }catch{if(alive.current)setError("Could not check the prison register. Reconnect before making another move.");}finally{loading.current=false;}
 },[]);
 useEffect(()=>{alive.current=true;const tick=setInterval(()=>setNow(Date.now()+offset.current),1000),poll=setInterval(()=>{if(!document.hidden&&!busy)void refresh();},5000);
  const focus=()=>{if(!document.hidden&&!busy)void refresh();};window.addEventListener("focus",focus);document.addEventListener("visibilitychange",focus);
  return()=>{alive.current=false;if(resetTimer.current)clearTimeout(resetTimer.current);clearInterval(tick);clearInterval(poll);window.removeEventListener("focus",focus);document.removeEventListener("visibilitychange",focus);};},[busy,refresh]);
 const sentenceDue=!!data.sentence&&Date.parse(data.sentence.release_at)<=now,attemptDue=!!data.attempt&&Date.parse(data.attempt.expires_at)<=now;
 useEffect(()=>{if(sentenceDue||attemptDue)void refresh();},[sentenceDue,attemptDue,refresh]);
 const released=initial.jailed&&!data.jailed;
 async function action(action:"start"|"tension",payload:Record<string,string|number>){
  setBusy(true);setError("");if(action==="start"){setNotice("");setResult(null);setTurn(0);setAngle(0);}
  try{
   const response=await createClient().rpc("prison_break_action",{p_action:action,p_payload:{...payload,season_id:data.season_id,request_id:crypto.randomUUID()}});
   const next=response.data as BreakResult|null;if(response.error||next?.error||!next)throw new Error(response.error?.message||next?.error||"The prison-break action could not be confirmed.");
   setNotice(next.outcome==="success"?"":next.message??"");setResult(next);if(typeof next.turn==="number")setTurn(next.turn);
   if(next.attempt)setData(current=>({...current,attempt:next.attempt!,lockpicks:Math.max(0,current.lockpicks-1)}));
   if(next.outcome==="continue"){setData(current=>current.attempt?{...current,attempt:{...current.attempt,attempts_left:next.attempts_left??current.attempt.attempts_left,last_turn:next.turn??0}}:current);resetTimer.current=setTimeout(()=>setTurn(0),650);}
   if(next.outcome==="success"||next.outcome==="caught"||next.outcome==="cancelled"){await new Promise(resolve=>setTimeout(resolve,650));await refresh();window.dispatchEvent(new Event("blackwater:game"));}
  }catch(caught){setError(caught instanceof Error?caught.message:"The guards interrupted the attempt. Refresh before retrying.");await refresh();}finally{setBusy(false);}
 }
 return <div className="prison-district prison-command" data-feature="prison-break-command">
  <nav className="prison-breadcrumb"><Link href="/dashboard">← Dashboard</Link><span>/</span><Link href="/districts">City map</Link><span>/ BLACKWATER ISLAND</span>{data.can_manage&&<Link href="/owner?section=prison">Owner controls ↗</Link>}</nav>
  <section className="prison-command-banner command-panel"><div><p className="eyebrow">BLACKWATER / MAXIMUM SECURITY</p><h1>Blackwater Island</h1><h2>Blackwater Island Prison</h2><p>Serve the sentence—or bring a lockpick and change somebody’s fate.</p></div><div className="prison-command-seal"><GameIcon name="lock" size={46}/><strong>CELL BLOCK A</strong><span>GUARDED WATERS · CONTROLLED ACCESS</span></div></section>
  <div className="prison-command-strip"><span><GameIcon name="lock"/><b>{data.lockpicks}</b> lockpicks carried</span><span><GameIcon name="respect"/><b>+{data.reward_power}</b> power per success</span><span><GameIcon name="people"/><b>{data.inmates.length}</b> available inmates</span><span><GameIcon name="trophy"/><b>{data.my_breakouts}</b> your breakouts</span></div>
  {(notice||error)&&<div className={"command-notice prison-notice"+(error?" error":"")} role={error?"alert":"status"}><span>{error||notice}</span><button aria-label="Dismiss notice" onClick={()=>{setError("");setNotice("");}}>×</button></div>}
  {data.jailed&&data.sentence?<div className="prison-command-grid custody"><section className="command-panel prison-custody-card"><header className="command-panel-head"><h2>Your custody record</h2><span className="prison-live">IN CUSTODY</span></header><h3>Serving your sentence</h3><p>You are held on Blackwater Island until the clock reaches zero or another player gets you through the lock.</p><div className="prison-countdown"><span>TIME REMAINING</span><strong role="timer" aria-live="off">{sentenceCountdown(data.sentence.release_at,now)}</strong><small>Release at {new Date(data.sentence.release_at).toLocaleString()}</small></div><dl><div><dt>Location</dt><dd>Cell Block A</dd></div><div><dt>Reason</dt><dd>{data.sentence.reason}</dd></div></dl><button className="command-more" onClick={()=>void refresh()}>Check prison status <GameIcon name="refresh" size={14}/></button><Link className="command-button" href="/support"><span>Contact support</span><GameIcon name="arrow"/></Link></section><Rules/><Leaderboard data={data}/></div>:
  <div className="prison-command-grid"><Inmates data={data} busy={busy} now={now} start={sentence_id=>void action("start",{sentence_id})}/><main className="command-panel prison-game-panel">{data.attempt?<LockGame attempt={data.attempt} now={now} busy={busy} angle={angle} turn={turn} onAngle={value=>{setAngle(value);setTurn(0);}} onTension={()=>void action("tension",{attempt_id:data.attempt!.id,angle})}/>:result?.outcome==="success"?<div className="prison-outcome success"><GameIcon name="lock" size={58}/><p className="eyebrow">CELL DOOR OPEN</p><h2>Clean extraction.</h2><p>{result.message}</p><button className="command-button" onClick={()=>{setResult(null);setNotice("");}}><span>Return to inmate register</span><GameIcon name="arrow"/></button></div>:<div className="prison-game-brief"><span className="prison-lock-emblem"><GameIcon name="lock" size={70}/></span><p className="eyebrow">PRISON-BREAK OPERATION</p><h2>Pick the lock.<br/>Beat the guard.</h2><p>Select an inmate from the register. One lockpick is consumed when the attempt begins. You get five tension checks and 90 seconds to find the lock’s hidden angle.</p><ol><li><b>01</b><span>Move the pick left or right.</span></li><li><b>02</b><span>Apply tension and watch the cylinder.</span></li><li><b>03</b><span>Reach 90° to open the cell.</span></li></ol><strong className="prison-risk">FAILURE: YOUR RELEASE TIME WILL MATCH THE TARGET INMATE.</strong></div>}</main><div className="prison-command-right"><Leaderboard data={data}/><Rules/></div></div>}
  {!data.jailed&&released&&<div className="prison-release command-panel"><GameIcon name="shield"/><div><h2>You’re free to leave.</h2><p>Your sentence has ended. The ferry is ready.</p></div><Link className="command-button" href="/dashboard"><span>Return to the city</span><GameIcon name="arrow"/></Link></div>}
 </div>;
}

function Inmates({data,busy,now,start}:{data:PrisonState;busy:boolean;now:number;start:(sentence:string)=>void}){
 return <aside className="command-panel prison-inmates"><header className="command-panel-head"><h2>Inmate intelligence</h2><button className="command-more" onClick={()=>window.location.reload()}><GameIcon name="refresh" size={13}/> Refresh</button></header><p className="command-subtitle">Active sentences · shortest time first</p><div className="prison-inmate-list">{data.inmates.map(inmate=><article key={inmate.sentence_id}><div className="prison-inmate-number">#{inmate.player_id.slice(0,4).toUpperCase()}</div><h3>{inmate.handle}</h3><span><GameIcon name="clock" size={14}/>{sentenceCountdown(inmate.release_at,now)}</span><button className="command-button" disabled={busy||!data.lockpicks||!!data.attempt} onClick={()=>start(inmate.sentence_id)}><GameIcon name="lock" size={16}/><span>{data.attempt?"Attempt active":data.lockpicks?"Plan jailbreak":"Lockpick required"}</span><GameIcon name="arrow" size={14}/></button></article>)}{!data.inmates.length&&<p className="command-empty">No other players are currently serving an active sentence.</p>}</div><div className="prison-kit"><GameIcon name="inventory"/><div><strong>Your kit</strong><span>{data.lockpicks} single-use {data.lockpicks===1?"lockpick":"lockpicks"}</span></div><Link href="/bin-diving">Find more ↗</Link></div></aside>;
}
function Leaderboard({data}:{data:PrisonState}){
 return <section className="command-panel prison-leaderboard"><header className="command-panel-head"><h2>Breakout leaderboard</h2><GameIcon name="trophy" size={17}/></header><p className="command-subtitle">Most successful extractions · this season</p>{data.leaderboard.length?<ol>{data.leaderboard.map(row=><li key={row.player_id}><b>{String(row.rank).padStart(2,"0")}</b><span>{row.handle}</span><strong>{row.breakouts}</strong></li>)}</ol>:<p className="command-empty">No one has opened a cell yet. The first name in the record book could be yours.</p>}<footer><span>Your position</span><strong>{data.my_rank?`#${data.my_rank}`:"Unranked"}</strong><small>{data.my_breakouts} successful</small></footer></section>;
}
function Rules(){return <aside className="command-panel prison-rules"><header className="command-panel-head"><h2>Operation rules</h2><GameIcon name="shield" size={17}/></header><ol><li><b>01</b><span>A lockpick is consumed when you start.</span></li><li><b>02</b><span>Success frees the inmate and awards power.</span></li><li><b>03</b><span>Five failed tensions get you caught.</span></li><li><b>04</b><span>Your sentence then matches their release time.</span></li></ol></aside>}

