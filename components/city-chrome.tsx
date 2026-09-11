"use client";
import {useCallback,useEffect,useRef,useState,type FormEvent} from "react";
import Link from "next/link";
import {usePathname} from "next/navigation";
import {createClient} from "@/lib/supabase/client";
import type {SocialState} from "@/lib/social";
import {UsernameForm} from "@/components/username-form";
import {LogoutButton} from "@/components/logout-button";
function UsernameGate(){
 const dialog=useRef<HTMLDialogElement>(null);
 useEffect(()=>{dialog.current?.showModal();},[]);
 return <dialog className="username-gate" ref={dialog} onCancel={e=>e.preventDefault()} aria-labelledby="username-title"><p className="eyebrow">YOUR BLACKWATER IDENTITY</p><h2 id="username-title">Choose your username.</h2><p>Your empire already has a beginning. Give it a name the city will remember.</p><UsernameForm onSaved={()=>window.location.reload()}/><LogoutButton/></dialog>;
}
export function CityChrome({children}:{children:React.ReactNode}){
 const path=usePathname();
 const [data,setData]=useState<SocialState|null>(null),[stale,setStale]=useState(false),[open,setOpen]=useState(false);
 const [body,setBody]=useState(""),[busy,setBusy]=useState(false),[error,setError]=useState("");
 const alive=useRef(false),reading=useRef(false),writing=useRef(false),feed=useRef<HTMLDivElement>(null),nearBottom=useRef(true),toggle=useRef<HTMLButtonElement>(null);
 const refresh=useCallback(async()=>{
  if(reading.current||document.hidden)return;
  reading.current=true;
  try{
   const {data:next,error}=await createClient().rpc("social_state");
   if(error||!next)throw error;
   if(alive.current){setData(next as SocialState);setStale(false);}
  }catch{if(alive.current)setStale(true);}
  finally{reading.current=false;}
 },[]);
 useEffect(()=>{
  alive.current=true;void refresh();
  const timer=window.setInterval(()=>void refresh(),Math.max(3,data?.poll_seconds||5)*1000);
  const visible=()=>{if(!document.hidden)void refresh();};
  document.addEventListener("visibilitychange",visible);window.addEventListener("focus",visible);window.addEventListener("blackwater:identity",visible);
  return ()=>{alive.current=false;window.clearInterval(timer);document.removeEventListener("visibilitychange",visible);window.removeEventListener("focus",visible);window.removeEventListener("blackwater:identity",visible);};
 },[refresh,data?.poll_seconds]);
 useEffect(()=>{if(nearBottom.current&&feed.current)feed.current.scrollTop=feed.current.scrollHeight;},[data?.chat,open]);
 useEffect(()=>{
  if(!open)return;
  const close=(e:KeyboardEvent)=>{if(e.key==="Escape"){setOpen(false);toggle.current?.focus();}};
  window.addEventListener("keydown",close);return ()=>window.removeEventListener("keydown",close);
 },[open]);
 async function action(action:string,payload:Record<string,string>){
  if(writing.current)return;writing.current=true;setBusy(true);setError("");
  try{
   const {data:result,error}=await createClient().rpc("community_action",{action,payload});
   if(error||result?.error)throw new Error(result?.error||"Could not send your message. Try again.");
   if(action==="chat"){setBody("");nearBottom.current=true;}await refresh();
  }catch(e){setError(e instanceof Error?e.message:"Chat could not be updated.");}
  finally{writing.current=false;setBusy(false);}
 }
 function send(e:FormEvent){e.preventDefault();if(body.trim())void action("chat",{body:body.trim()});}
 const owner=data?.permissions.includes("roles.manage"),staff=!!data?.permissions.length;
 const links=[["/dashboard","Empire"],["/players","Players"],["/seasons?view=rankings","Leaderboards"],["/seasons","Seasons"],["/support","Support"]];
 const count=data&&!stale?data.online_count.toLocaleString("en-US"):"—";
 return <div className={"connected-city"+(open?" chat-is-open":"")}>
  <header className="city-topbar"><div className="city-top-row"><Link className="city-brand" href="/dashboard" aria-label="Blackwater empire"><b>BW</b><span>BLACKWATER<small>MAFIA</small></span></Link><nav aria-label="City navigation">{links.map(([href,label])=><Link key={label} href={href} className={path===href?"current":""}>{label}</Link>)}{staff&&<Link className="city-owner-link" href={owner?"/owner":"/staff"}>{owner?"Owner panel":"Staff panel"}</Link>}</nav><Link className="city-account" href="/account" aria-label="Your account">{data?.username?.slice(0,1)||"◈"}</Link></div><div className="city-status-row"><Link href="/players?online=1"><span className={stale?"presence-dot offline":"presence-dot"}/><strong>{count} online</strong></Link><Link href="/seasons"><span className="city-status-label">CURRENT SEASON</span> {data?.season.name||"Loading season…"} <span className="season-state">{data?.season.status}</span></Link>{stale&&<span className="city-reconnecting">Reconnecting…</span>}</div></header>
  <div className="city-page"><main id="main">{children}</main></div>
  <button ref={toggle} className="chat-toggle" onClick={()=>setOpen(!open)} aria-expanded={open} aria-controls="city-chat">City chat <span>{count}</span></button>
  {open&&<button className="chat-backdrop" aria-label="Close chat backdrop" onClick={()=>setOpen(false)}/>}
  <aside id="city-chat" className="city-chat" aria-label="City chat"><div className="chat-heading"><div><p className="eyebrow">THE CITY NEVER SLEEPS</p><h2>City chat<span className="presence-dot"/></h2></div><button className="chat-close" aria-label="Close city chat" onClick={()=>{setOpen(false);toggle.current?.focus();}}>×</button></div><p className="chat-connection">{stale?<>Connection interrupted. <button onClick={()=>void refresh()}>Reconnect</button></>:data?<>{count} players online · Public channel</>:"Connecting to Blackwater…"}</p>
   <div className="chat-feed" ref={feed} role="log" aria-label="City messages" aria-live="polite" onScroll={()=>{const el=feed.current;if(el)nearBottom.current=el.scrollHeight-el.scrollTop-el.clientHeight<70;}}>
    {data?.chat.map(m=><article className={"wire-message"+(m.player_id===data.player_id?" own-message":"")} key={m.id}><div className="wire-author"><span className="wire-avatar" aria-hidden="true">{m.username.slice(0,1).toUpperCase()}</span><Link href={"/players/"+m.player_id}>{m.username}</Link>{m.role!=="player"&&<span className="role-badge">{m.role}</span>}<time dateTime={m.created_at} title={m.created_at}>{new Date(m.created_at).toLocaleTimeString("en-GB",{hour:"2-digit",minute:"2-digit",timeZone:"UTC"})}</time></div><p>{m.body}</p>{m.player_id===data.player_id&&<button className="chat-remove" disabled={busy} onClick={()=>void action("delete_own_chat",{id:m.id})} aria-label={"Remove your message: "+m.body.slice(0,40)}>Remove</button>}</article>)}
    {data&&!data.chat.length&&<div className="chat-empty"><span>◈</span><p>Make the first connection.</p><small>Talk trade. Find allies. Put your name on the street.</small></div>}
   </div><form className="chat-compose" onSubmit={send}><label htmlFor="city-message">Message the city</label><textarea id="city-message" maxLength={1000} value={body} onChange={e=>setBody(e.target.value)} placeholder={data?.muted?"You are currently muted.":"Talk trade. Make connections."} required disabled={!data||data.muted||!data.username_claimed}/><div><small>{body.length}/1000</small><button className="button small" disabled={busy||!data||data.muted||!data.username_claimed||!body.trim()}>{busy?"Sending…":"Send ↗"}</button></div>{error&&<p className="notice error" role="alert">{error}</p>}{data?.muted&&<p className="hint">Your chat access is muted. See <Link href="/support">Support</Link> for account notices.</p>}</form>
  </aside>{data&&!data.username_claimed&&<UsernameGate/>}
 </div>;
}
