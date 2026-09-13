"use client";
import Link from "next/link";
import {useCallback,useEffect,useRef,useState} from "react";
import {createClient} from "@/lib/supabase/client";
import {sentenceCountdown,type PrisonState} from "@/lib/prison";

export function PrisonDistrict({initial}:{initial:PrisonState}) {
 const [data,setData]=useState(initial),[now,setNow]=useState(Date.parse(initial.server_time)),[error,setError]=useState("");
 const offset=useRef(Date.parse(initial.server_time)-Date.now()),loading=useRef(false),alive=useRef(true);
 const refresh=useCallback(async()=>{
  if(loading.current)return;loading.current=true;
  try{const result=await createClient().rpc("prison_state");if(result.error||!result.data)throw new Error();
   if(alive.current){offset.current=Date.parse(result.data.server_time)-Date.now();setNow(Date.parse(result.data.server_time));setData(result.data);setError("");window.dispatchEvent(new CustomEvent("blackwater:custody",{detail:result.data}));}
  }catch{if(alive.current)setError("Could not check your sentence. Reconnect to confirm your release.");}finally{loading.current=false;}
 },[]);
 useEffect(()=>{alive.current=true;const tick=setInterval(()=>setNow(Date.now()+offset.current),1000),poll=setInterval(()=>{if(!document.hidden)void refresh();},5000);
  const focus=()=>{if(!document.hidden)void refresh();};window.addEventListener("focus",focus);document.addEventListener("visibilitychange",focus);
  return()=>{alive.current=false;clearInterval(tick);clearInterval(poll);window.removeEventListener("focus",focus);document.removeEventListener("visibilitychange",focus);};},[refresh]);
 const due=!!data.sentence&&Date.parse(data.sentence.release_at)<=now;
 useEffect(()=>{if(due)void refresh();},[due,refresh]);
 const released=initial.jailed&&!data.jailed;
 return <div className="prison-district">
  <header className="prison-heading"><div><p className="eyebrow">BLACKWATER / PRISON DISTRICT</p><h1>Blackwater Island</h1></div><span className="prison-seal">CITY PENITENTIARY · EST. 1908</span></header>
  <section className="prison-hero" aria-label="Blackwater Island Prison">
   <div className="prison-hero-copy"><p className="eyebrow">MAXIMUM SECURITY</p><h2>Beyond the harbor.<br/><em>Behind bars.</em></h2><p>The city moves on across the water.<br/>Here, every minute belongs to your sentence.</p><span className="prison-security">● GUARDED WATERS · CONTROLLED ACCESS</span></div>
   <svg className="prison-art" viewBox="0 0 700 430" aria-hidden="true"><defs><linearGradient id="prison-sky" x2="0" y2="1"><stop stopColor="#162a35"/><stop offset="1" stopColor="#52615e"/></linearGradient><pattern id="prison-windows" width="36" height="38" patternUnits="userSpaceOnUse"><rect x="12" y="8" width="12" height="20" fill="#101c22"/><path d="M16 8v20m4-20v20" stroke="#7a7b69"/></pattern></defs><path d="M0 0h700v430H0z" fill="url(#prison-sky)"/><circle cx="555" cy="80" r="34" fill="#b5b198" opacity=".3"/><path d="M0 340Q180 290 340 330T700 325V430H0Z" fill="#162832"/><path d="M75 338L142 290H545L631 354L535 377H155Z" fill="#343d3c"/><path d="M160 180H545V313H160Z" fill="#6b6b5c"/><path d="M160 180H545V310H160Z" fill="url(#prison-windows)"/><path d="M133 145H187V325H133ZM515 145H570V325H515Z" fill="#686b5f"/><path d="M124 143L160 112L196 143ZM506 143L542 112L579 143Z" fill="#263239"/><path d="M130 158h60m-58 9h56m328-9h58m-56 9h54" stroke="#b2a485" strokeWidth="4"/><path d="M293 310V226Q350 170 407 226V310Z" fill="#24333a"/><path d="M305 310v-81m18 81v-94m18 94v-100m18 100v-100m18 100v-94m18 94v-81m-90 26h90" stroke="#94917c" strokeWidth="4"/><path d="M94 327H600M91 322V295M604 327v-30" stroke="#8d8872" strokeWidth="5"/><path d="M100 391h190m150 9h160M8 368h68m500 13h115" stroke="#6f807e" opacity=".5"/></svg>
  </section>
  <div className="prison-columns"><section className="prison-status command-panel" aria-live="polite">
   <p className="eyebrow">{data.jailed?"YOUR CUSTODY RECORD":released?"RELEASE CONFIRMED":"VISITOR INFORMATION"}</p>
   <h2>{data.jailed?"Serving your sentence":released?"You’re free to leave.":"Blackwater Island Prison"}</h2>
   {data.jailed&&data.sentence?<><p>You are being held on Blackwater Island. City travel and gameplay resume after your release.</p><div className="prison-countdown"><span>TIME REMAINING</span><strong role="timer" aria-live="off">{sentenceCountdown(data.sentence.release_at,now)}</strong><small>Release at {new Date(data.sentence.release_at).toLocaleString()}</small></div><dl><div><dt>Location</dt><dd>Blackwater Island Prison</dd></div><div><dt>Reason</dt><dd>{data.sentence.reason}</dd></div></dl><p className="prison-note">Your sentence continues while you’re offline. Release is automatic when your time is served.</p></>:<><p>{released?"Your sentence has ended. The ferry is ready to take you back to the city.":"All jailed players are transferred here and remain in custody until their sentence ends or the Owner authorizes release."}</p><Link className="command-button" href="/dashboard">{released?"Return to the city":"Back to city map"} <span>→</span></Link></>}
   {error&&<p role="alert">{error}</p>}<button className="prison-refresh" onClick={()=>void refresh()}>Check prison status</button>
  </section><aside className="prison-rules command-panel"><p className="eyebrow">ISLAND REGULATIONS</p><h2>Time is the price.</h2><ol><li><span>01</span><div><strong>One destination</strong><p>Every jail sentence is served on Blackwater Island.</p></div></li><li><span>02</span><div><strong>The gates stay closed</strong><p>You cannot travel to another district while in custody.</p></div></li><li><span>03</span><div><strong>A way back</strong><p>Serve your time or receive an authorized early release.</p></div></li></ol><Link href="/support">Contact support →</Link>{data.can_manage&&<Link href="/owner?section=prison">Open prison administration →</Link>}</aside></div>
 </div>;
}

