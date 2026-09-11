"use client";
import {useCallback,useEffect,useRef,useState,type FormEvent} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase/client";
import type {DirectoryState} from "@/lib/social";
export function PlayerDirectory({initial,initialOnline=false}:{initial:DirectoryState;initialOnline?:boolean}){
 const [data,setData]=useState(initial),[search,setSearch]=useState(""),[query,setQuery]=useState(""),[online,setOnline]=useState(initialOnline),[busy,setBusy]=useState(false),[error,setError]=useState("");
 const version=useRef(0);
 const refresh=useCallback(async(q:string,on:boolean,offset=0)=>{
  const current=++version.current;setBusy(true);
  try{const {data:next,error}=await createClient().rpc("player_directory",{p_search:q,p_online:on,p_offset:offset});if(error||!next)throw error;if(current===version.current){setData(next);setError("");}}
  catch{if(current===version.current)setError("Could not refresh the players. Showing the last received list.");}
  finally{if(current===version.current)setBusy(false);}
 },[]);
 useEffect(()=>{const timer=window.setInterval(()=>{if(!document.hidden)void refresh(query,online,data.offset);},20000);return ()=>window.clearInterval(timer);},[refresh,query,online,data.offset]);
 useEffect(()=>()=>{++version.current;},[]);
 function submit(e:FormEvent){e.preventDefault();setQuery(search.trim());void refresh(search.trim(),online);}
 return <div className="control-layout directory-page"><div className="control-heading"><div><p className="eyebrow">THE PEOPLE OF BLACKWATER</p><h1>Respect is earned.</h1><p>The city's players, ranked by respect in {data.season.name}.</p></div><div className="directory-stats"><strong><span className="presence-dot"/>{data.online_count} online</strong><span>Your rank {data.my_rank?"#"+data.my_rank:"—"}</span></div></div>
  <div className="directory-filters"><form onSubmit={submit}><label className="sr-only" htmlFor="player-search">Search players</label><input id="player-search" placeholder="Find a player…" value={search} maxLength={64} onChange={e=>setSearch(e.target.value)}/><button className="button small" disabled={busy}>Search</button></form><label className="online-filter"><input type="checkbox" checked={online} onChange={e=>{setOnline(e.target.checked);void refresh(query,e.target.checked);}}/>Online only</label><button className="button small ghost" disabled={busy} onClick={()=>void refresh(query,online,data.offset)}>Refresh players</button></div>
  {error&&<p role="alert" className="notice error">{error}</p>}
  <section className="game-panel"><div className="panel-heading"><h2>Player rankings</h2><span>{data.total} players</span></div><div className="table-scroll"><table className="market-table player-table"><thead><tr><th>Rank</th><th>Player</th><th>Respect</th><th>Status</th></tr></thead><tbody>{data.players.map(p=><tr key={p.id}><td className="gold">#{p.rank}</td><td><Link className="directory-name" href={"/players/"+p.id}><span className="wire-avatar" aria-hidden="true">{p.username.slice(0,1)}</span>{p.username}</Link>{p.role!=="player"&&<span className="role-badge">{p.role}</span>}</td><td>{Number(p.respect).toLocaleString("en-US")}</td><td><span className={p.online?"presence-dot":"presence-dot offline"}/>{p.online?"Online":"Offline"}</td></tr>)}</tbody></table></div>{!data.players.length&&<p className="panel-empty">No players match this search.</p>}<div className="directory-pagination"><button className="button small ghost" disabled={busy||data.offset===0} onClick={()=>void refresh(query,online,Math.max(0,data.offset-data.page_size))}>Previous</button><span>{data.total?data.offset+1:0}–{Math.min(data.offset+data.page_size,data.total)} of {data.total}</span><button className="button small ghost" disabled={busy||data.offset+data.page_size>=data.total} onClick={()=>void refresh(query,online,data.offset+data.page_size)}>Next</button></div></section><p className="hint">Equal respect shares a rank. Search and online filters preserve the full season ranking. Online status updates while players are active.</p>
 </div>;
}
