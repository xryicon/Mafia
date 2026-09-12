"use client";
import {useCallback,useEffect,useLayoutEffect,useRef,useState} from "react";
import Link from "next/link";
import {usePathname} from "next/navigation";
import {createClient} from "@/lib/supabase/client";
import {money,type GameState} from "@/lib/game";
import type {CityState} from "@/lib/city";
import {PlayerAvatar} from "@/components/player-avatar";
import {Brand} from "@/components/brand";
import {GameIcon} from "@/components/game-icon";
import {UsernameForm} from "@/components/username-form";
import {LogoutButton} from "@/components/logout-button";
function UsernameGate(){
 const dialog=useRef<HTMLDialogElement>(null);
 useEffect(()=>{dialog.current?.showModal();},[]);
 return <dialog className="username-gate" ref={dialog} onCancel={e=>e.preventDefault()} aria-labelledby="username-title"><p className="eyebrow">YOUR BLACKWATER IDENTITY</p><h2 id="username-title">Choose your username.</h2><p>Give your empire a name the city will remember.</p><UsernameForm onSaved={()=>window.location.reload()}/><LogoutButton/></dialog>;
}
export function CityChrome({children}:{children:React.ReactNode}){
 const path=usePathname(),[data,setData]=useState<CityState|null>(null),[stale,setStale]=useState(false);
 const [summary,setSummary]=useState<{stock:number|null;unread:number|null}|null>(null);
 const alive=useRef(false),reading=useRef(false),account=useRef<HTMLDetailsElement>(null);
 const refresh=useCallback(async()=>{
  if(reading.current||document.hidden)return;reading.current=true;
  try{
   const client=createClient();
   const [city,game,mail]=await Promise.allSettled([client.rpc("city_status"),client.rpc("game_state"),client.rpc("telegram_state")]);
   if(!alive.current)return;
   if(city.status==="fulfilled"&&!city.value.error&&city.value.data){setData(city.value.data);setStale(false);}else setStale(true);
   const inventory=game.status==="fulfilled"&&!game.value.error?(game.value.data as GameState|null)?.inventory:null;
   const unread=mail.status==="fulfilled"&&!mail.value.error?mail.value.data?.unread:null;
   setSummary({stock:Array.isArray(inventory)?inventory.reduce((total,item)=>total+item.quantity,0):null,unread:typeof unread==="number"?unread:null});
  }
  catch{if(alive.current)setStale(true);}finally{reading.current=false;}
 },[]);
 useEffect(()=>{
  alive.current=true;void refresh();const timer=window.setInterval(()=>void refresh(),Math.max(15,data?.poll_seconds||30)*1000);
  const visible=()=>{if(!document.hidden)void refresh();};
  document.addEventListener("visibilitychange",visible);window.addEventListener("focus",visible);window.addEventListener("blackwater:identity",visible);window.addEventListener("blackwater:game",visible);
  return ()=>{alive.current=false;window.clearInterval(timer);document.removeEventListener("visibilitychange",visible);window.removeEventListener("focus",visible);window.removeEventListener("blackwater:identity",visible);window.removeEventListener("blackwater:game",visible);};
 },[refresh,data?.poll_seconds]);
 useEffect(()=>{void refresh();},[path,refresh]);
 useLayoutEffect(()=>{if(account.current)account.current.open=false;},[path]);
 useEffect(()=>{
  const close=(e:PointerEvent)=>{if(account.current&&!account.current.contains(e.target as Node))account.current.open=false;};
  const escape=(e:KeyboardEvent)=>{if(e.key==="Escape"){if(account.current?.open){account.current.open=false;account.current.querySelector("summary")?.focus();}}};
  document.addEventListener("pointerdown",close);document.addEventListener("keydown",escape);return()=>{document.removeEventListener("pointerdown",close);document.removeEventListener("keydown",escape);};
 },[]);
 const links=[["/dashboard","Dashboard","home"],["/market","Market","trade"],["/properties","Properties","property"],["/bank","Bank","bank"],["/gangs","Gangs","people"],["/telegrams","Telegrams","mail"]];
 const blank=["/properties"].includes(path);
 useEffect(()=>{const update=(event:Event)=>setSummary((event as CustomEvent).detail);window.addEventListener("blackwater:dashboard",update);return()=>window.removeEventListener("blackwater:dashboard",update);},[]);
 const active=(href:string)=>path===href||path.startsWith(href+"/");
 return <div className={"estate-city fresh-city command-city"+(blank?" fresh-page":"")+(path==="/dashboard"?" command-dashboard-page":"")}>
  <header className="estate-header"><Brand href="/dashboard" className="estate-brand" status={<><span className={"presence-dot"+(stale?" offline":"")}/><span>{data&&!stale?data.online_count.toLocaleString("en-US"):"—"} online</span></>}/><span className="command-header-tagline">A PLAYER-DRIVEN CRIME ECONOMY</span><nav className="estate-nav" aria-label="Game navigation">{links.map(([href,name,icon])=><Link href={href} key={href} aria-current={active(href)?"page":undefined}><GameIcon name={icon} size={18}/><span>{name}</span>{href==="/telegrams"&&!!summary?.unread&&<b className="command-nav-badge" aria-hidden="true">{summary.unread}</b>}</Link>)}</nav>
  <div className="estate-player-tools"><div className="header-wallet" aria-label="Cash balance"><span className="wallet-label">CASH</span><strong className="header-cash">{data?money(data.player.cash):"—"}</strong></div>
  <Link href="/market?view=inventory" className="command-header-stock" aria-label="Inventory stock"><GameIcon name="inventory" size={22}/>{summary?.stock?.toLocaleString("en-US")??"—"}</Link>
  <Link className="command-header-bell" href="/telegrams" aria-label="Telegram notifications"><GameIcon name="bell" size={21}/>{!!summary?.unread&&<b aria-hidden="true">{summary.unread}</b>}</Link>
  <details className="estate-account-menu" ref={account}><summary aria-label="Player menu"><PlayerAvatar className="don-portrait" src={data?.avatar_url} size={36}/><div><span className="estate-player-name">{data?.username||"Your account"} <i>⌄</i></span><span className="estate-player-numbers"><span className="header-power">Power <strong>{data?.player.power?.toLocaleString("en-US")??"—"}</strong></span><span className="header-rank" title="Rank">{data?.player.rank||"—"}</span></span></div></summary>
   <div className="estate-dropdown"><p className="eyebrow">YOUR BLACKWATER</p><p className="account-identity">{data?.username||"Your account"}<small>Power {data?.player.power?.toLocaleString("en-US")??"—"} · {data?.player.rank||"—"}</small></p><Link href="/players">Players & respect</Link><Link href="/seasons?view=rankings">Leaderboards</Link><Link href="/seasons">Seasons</Link><Link href="/support">Support</Link>{!!data?.permissions.length&&<Link className="owner-menu-link" href={data.permissions.includes("roles.manage")?"/owner":"/staff"}>{data.permissions.includes("roles.manage")?"Owner panel":"Staff panel"}</Link>}<Link href="/districts">City map & districts</Link><Link href="/ledger">Financial history</Link><Link href="/account">Account & security</Link><LogoutButton/></div>
  </details></div></header>
  {stale&&<div className="estate-connection" role="status">Connection paused. <button onClick={()=>void refresh()}>Refresh city status</button></div>}
  <main id="main">{children}</main>
  {!blank&&<footer className="estate-footer"><Brand href="/dashboard"/><p>A PLAYER-DRIVEN CRIME ECONOMY <span>│</span> AMBITION LIVES HERE.</p><nav aria-label="Game information"><Link href="/seasons">Seasons</Link><Link href="/players">Players</Link><Link href="/support">Help</Link></nav><small>SAME PLAYERS.<br/>A DIFFERENT TOMORROW.</small></footer>}
  {data&&!data.username_claimed&&<UsernameGate/>}
 </div>;
}
