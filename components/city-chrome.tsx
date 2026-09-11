"use client";
import {useCallback,useEffect,useLayoutEffect,useRef,useState} from "react";
import Link from "next/link";
import {usePathname} from "next/navigation";
import {createClient} from "@/lib/supabase/client";
import {money} from "@/lib/game";
import type {CityState} from "@/lib/city";
import {Brand} from "@/components/brand";
import {GameIcon} from "@/components/game-icon";
import {UsernameForm} from "@/components/username-form";
import {LogoutButton} from "@/components/logout-button";
function UsernameGate(){
 const dialog=useRef<HTMLDialogElement>(null);
 useEffect(()=>{dialog.current?.showModal();},[]);
 return <dialog className="username-gate" ref={dialog} onCancel={e=>e.preventDefault()} aria-labelledby="username-title"><p className="eyebrow">YOUR BLACKWATER IDENTITY</p><h2 id="username-title">Choose your username.</h2><p>Give your empire a name the city will remember.</p><UsernameForm onSaved={()=>window.location.reload()}/><LogoutButton/></dialog>;
}
function Portrait(){return <svg viewBox="0 0 44 44" className="don-portrait" aria-hidden="true"><defs><radialGradient id="portrait-glow"><stop stopColor="#465459"/><stop offset="1" stopColor="#081315"/></radialGradient></defs><circle cx="22" cy="22" r="21" fill="url(#portrait-glow)" stroke="#b28b54"/><path d="m15 18 2-9 10 1 4 9 5 2-24 2-4-3 7-2Zm2 5 12-1-1 10 6 9H10l7-10Z" fill="#020809"/><path d="m17 18 12 1" stroke="#756d56" strokeWidth="1.4"/></svg>;}
export function CityChrome({children}:{children:React.ReactNode}){
 const path=usePathname(),[data,setData]=useState<CityState|null>(null),[stale,setStale]=useState(false);
 const alive=useRef(false),reading=useRef(false),account=useRef<HTMLDetailsElement>(null);
 const refresh=useCallback(async()=>{
  if(reading.current||document.hidden)return;reading.current=true;
  try{const result=await createClient().rpc("city_status");if(result.error||!result.data)throw result.error;if(alive.current){setData(result.data);setStale(false);}}
  catch{if(alive.current)setStale(true);}finally{reading.current=false;}
 },[]);
 useEffect(()=>{
  alive.current=true;void refresh();const timer=window.setInterval(()=>void refresh(),Math.max(15,data?.poll_seconds||30)*1000);
  const visible=()=>{if(!document.hidden)void refresh();};
  document.addEventListener("visibilitychange",visible);window.addEventListener("focus",visible);window.addEventListener("blackwater:identity",visible);window.addEventListener("blackwater:game",visible);
  return ()=>{alive.current=false;window.clearInterval(timer);document.removeEventListener("visibilitychange",visible);window.removeEventListener("focus",visible);window.removeEventListener("blackwater:identity",visible);window.removeEventListener("blackwater:game",visible);};
 },[refresh,data?.poll_seconds]);
 useLayoutEffect(()=>{if(account.current)account.current.open=false;},[path]);
 useEffect(()=>{
  const close=(e:PointerEvent)=>{if(account.current&&!account.current.contains(e.target as Node))account.current.open=false;};
  const escape=(e:KeyboardEvent)=>{if(e.key==="Escape"){if(account.current?.open){account.current.open=false;account.current.querySelector("summary")?.focus();}}};
  document.addEventListener("pointerdown",close);document.addEventListener("keydown",escape);return()=>{document.removeEventListener("pointerdown",close);document.removeEventListener("keydown",escape);};
 },[]);
 const links=[["/dashboard","Dashboard","home"],["/market","Market","trade"],["/properties","Properties","property"],["/districts","Districts","district"],["/gangs","Gangs","people"],["/telegrams","Telegrams","mail"]];
 const blank=["/dashboard","/properties","/telegrams"].includes(path);
 const active=(href:string)=>path===href||path.startsWith(href+"/");
 return <div className={"estate-city fresh-city"+(blank?" fresh-page":"")}>
  <header className="estate-header"><Brand href="/dashboard" className="estate-brand" status={<><span className={"presence-dot"+(stale?" offline":"")}/><span>{data&&!stale?data.online_count.toLocaleString("en-US"):"—"} online</span></>}/><nav className="estate-nav" aria-label="Game navigation">{links.map(([href,name,icon])=><Link href={href} key={href} aria-current={active(href)?"page":undefined}><GameIcon name={icon} size={18}/><span>{name}</span></Link>)}</nav>
  <div className="estate-player-tools"><div className="header-wallet" aria-label="Cash balance"><span className="wallet-label">CASH</span><strong className="header-cash">{data?money(data.player.cash):"—"}</strong></div>
  <details className="estate-account-menu" ref={account}><summary aria-label="Player menu"><Portrait/><div><span className="estate-player-name">{data?.username||"Your account"} <i>⌄</i></span><span className="estate-player-numbers"><span className="header-power">Power <strong>{data?.player.power?.toLocaleString("en-US")??"—"}</strong></span><span className="header-rank" title="Rank">{data?.player.rank||"—"}</span></span></div></summary>
   <div className="estate-dropdown"><p className="eyebrow">YOUR BLACKWATER</p><p className="account-identity">{data?.username||"Your account"}<small>Power {data?.player.power?.toLocaleString("en-US")??"—"} · {data?.player.rank||"—"}</small></p><Link href="/players">Players & respect</Link><Link href="/seasons?view=rankings">Leaderboards</Link><Link href="/seasons">Seasons</Link><Link href="/support">Support</Link>{!!data?.permissions.length&&<Link className="owner-menu-link" href={data.permissions.includes("roles.manage")?"/owner":"/staff"}>{data.permissions.includes("roles.manage")?"Owner panel":"Staff panel"}</Link>}<Link href="/ledger">Financial history</Link><Link href="/account">Account & security</Link><LogoutButton/></div>
  </details></div></header>
  {stale&&<div className="estate-connection" role="status">Connection paused. <button onClick={()=>void refresh()}>Refresh city status</button></div>}
  <main id="main">{children}</main>
  {!blank&&<footer className="estate-footer"><Brand href="/dashboard"/><p>A PLAYER-DRIVEN CRIME ECONOMY <span>│</span> AMBITION LIVES HERE.</p><nav aria-label="Game information"><Link href="/seasons">Seasons</Link><Link href="/players">Players</Link><Link href="/support">Help</Link></nav><small>SAME PLAYERS.<br/>A DIFFERENT TOMORROW.</small></footer>}
  {data&&!data.username_claimed&&<UsernameGate/>}
 </div>;
}
