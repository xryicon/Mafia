"use client";
import {useCallback,useEffect,useRef,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase/client";
import {PlayerAvatar} from "@/components/player-avatar";
import {ProfilePicture} from "@/components/profile-picture";
import {GameIcon} from "@/components/game-icon";
import {profileNumber,type PlayerProfile} from "@/lib/player-profile";
function ProfileEditor({data,onSave,onPicture,close}:{data:PlayerProfile;onSave:(description:string,version:number)=>void;onPicture:(src:string)=>void;close:()=>void}){
 const dialog=useRef<HTMLDialogElement>(null),[body,setBody]=useState(data.description),[busy,setBusy]=useState(false),[message,setMessage]=useState(""),[conflict,setConflict]=useState(false);
 useEffect(()=>{dialog.current?.showModal();},[]);
 async function save(e:React.FormEvent){e.preventDefault();if(busy)return;setBusy(true);setMessage("");
  try{const r=await createClient().rpc("profile_description",{p_description:body,p_version:data.description_version});
   if(r.error||r.data?.error){if(r.data?.conflict)setConflict(true);throw new Error(r.data?.error||"Your description could not be saved. Try again.");}
   onSave(r.data.description,r.data.description_version);setMessage(r.data.message);
  }catch(e){setMessage(e instanceof Error?e.message:"Please try again.");}finally{setBusy(false);}
 }
 return <dialog ref={dialog} className="pp-editor" aria-labelledby="pp-edit-title" onCancel={e=>{if(busy)e.preventDefault();else close();}}>
 <button className="pp-close" aria-label="Close profile editor" disabled={busy} onClick={close}>×</button>
 <p className="pp-eyebrow">YOUR NAME. YOUR STORY.</p><h2 id="pp-edit-title">Edit your profile</h2><p className="pp-editor-intro">A few words for the people of Blackwater.</p>
 <form onSubmit={save}><label htmlFor="pp-description">Profile description</label><textarea id="pp-description" value={body} onChange={e=>setBody(e.target.value)} maxLength={data.description_limit} rows={4} disabled={busy} placeholder="Tell the city a little about yourself…"/><div className="pp-editor-hint"><span>Visible to other players. Plain text only.</span><span>{body.length} / {data.description_limit}</span></div><button className="pp-gold" disabled={busy||conflict||body.trim().length>data.description_limit}>{busy?"Saving…":"Save description"}<GameIcon name="arrow" size={16}/></button>{message&&<p className="pp-feedback" role="status">{message}</p>}</form>
 <ProfilePicture initial={data.avatar_url} name={data.handle} onSaved={onPicture}/>
 </dialog>;
}
function RankingRows({rows,seasonId}:{rows:PlayerProfile["current"];seasonId?:string}){
 return <div className="pp-ranking-rows">{rows.map((r,i)=><Link key={String(r.season_id)+String(r.metric)+i} href={"/seasons?season="+encodeURIComponent(r.season_id??seasonId??"")+"&metric="+encodeURIComponent(r.metric??"respect")}><span>{r.label}</span><strong>#{profileNumber(r.rank)}</strong><small>{profileNumber(r.score)}</small><GameIcon name="arrow" size={14}/></Link>)}</div>;
}
export function PlayerProfileView({initial}:{initial:PlayerProfile}){
 const [data,setData]=useState(initial),[editing,setEditing]=useState(false),[notice,setNotice]=useState(""),[showAll,setShowAll]=useState(false);
 const request=useRef(0);
 const refresh=useCallback(async()=>{const version=++request.current;try{const r=await createClient().rpc("player_profile",{p_player:initial.player_id});if(r.error||!r.data)throw new Error();if(version===request.current){setData(r.data);setNotice("");}}catch{if(version===request.current)setNotice("Live updates paused. Refresh to reconnect.");}},[initial.player_id]);
 useEffect(()=>{if(editing)return;const update=()=>{if(!document.hidden)void refresh();};const timer=setInterval(update,45000);window.addEventListener("focus",update);return()=>{clearInterval(timer);window.removeEventListener("focus",update);request.current++;};},[editing,refresh]);
 const previousRespect=data.previous.find(r=>r.metric==="respect"),current=data.current;
 const pastSeasons=[...new Set(data.previous.map(r=>r.season_id))];
 const businesses=showAll?data.businesses:data.businesses.slice(0,4);
 const joined=new Date(data.joined_at).toLocaleDateString("en-GB",{day:"numeric",month:"short",year:"numeric",timeZone:"UTC"});
 return <div className="pp-page" data-feature="player-profiles">
 <nav className="pp-breadcrumb" aria-label="Profile location"><Link href="/players">Players</Link><span>›</span><span>{data.handle}</span><Link href="/dashboard">Back to the city <GameIcon name="arrow" size={13}/></Link></nav>
 <section className="pp-hero">
 <div className="pp-portrait-frame"><PlayerAvatar src={data.avatar_url} name={data.handle} className="pp-portrait" size={280}/><div className="pp-portrait-caption"><span>BLACKWATER</span><p>A name is earned.<br/>A legacy is built.</p></div></div>
 <div className="pp-identity"><div className="pp-presence"><i className={data.online?"online":""}/>{data.online?"ONLINE":"OFFLINE"}{data.is_self&&<span>YOUR PROFILE</span>}</div>
 <h1>{data.handle}</h1><div className="pp-title"><em>{data.title}</em><span>·</span>{data.gang?<Link href="/gangs">{data.gang.name}</Link>:<span>Independent</span>}{data.role!=="player"&&<b>{data.role}</b>}</div>
 <div className={"pp-description "+(!data.description?"empty":"")}>{data.description||"This player hasn’t added a description yet."}</div>
 <div className="pp-power-strip"><div><GameIcon name="respect" size={22}/><span>Power <small>Respect score</small></span><strong>{profileNumber(data.respect)}</strong></div><div><GameIcon name="ledger" size={22}/><span>Season rank <small>By respect</small></span><strong>{data.respect_rank?"#"+profileNumber(data.respect_rank):"—"}</strong></div><div><GameIcon name="clock" size={22}/><span>Previous season <small>By respect</small></span><strong>{previousRespect?"#"+profileNumber(previousRespect.rank):"—"}</strong></div></div>
 </div>
 <div className="pp-actions"><p>POWER<br/>MOVES<br/>PEOPLE.</p>{data.is_self?<><button className="pp-gold" onClick={()=>setEditing(true)}><GameIcon name="gear" size={17}/>Edit profile</button><Link className="pp-outline" href="/account"><GameIcon name="shield" size={16}/>Account settings</Link></>:<><Link className="pp-gold" href={"/telegrams?to="+encodeURIComponent(data.handle)}><GameIcon name="mail" size={17}/>Send Telegram</Link><Link className="pp-outline" href="/players"><GameIcon name="people" size={16}/>Player directory</Link></>}<Link className="pp-text-link" href="/seasons">Season leaderboards <GameIcon name="arrow" size={14}/></Link></div>
 </section>
 {notice&&<div className="pp-notice" role="status">{notice}<button onClick={()=>void refresh()}>Refresh profile</button></div>}
 <div className="pp-content"><section className="pp-panel pp-empire"><header><h2><GameIcon name="businesses" size={20}/>Empire & businesses</h2><span>{data.business_total} owned</span></header>
 <div className="pp-empire-banner"><img src="/art/foundry-small.webp" alt="" width={600} height={240}/><div><p>BUILT ON AMBITION</p><strong>{data.business_total} <small>business{data.business_total===1?"":"es"}</small></strong><span>{data.plot_count} owned plot{data.plot_count===1?"":"s"} · {data.districts.length} district{data.districts.length===1?"":"s"}</span></div></div>
 {businesses.length?<div className="pp-business-list">{businesses.map(b=><Link key={b.id} href={b.href}><span className="pp-business-icon"><GameIcon name={b.kind==="production"?"production":"businesses"} size={24}/></span><div><h3>{b.name}</h3><span>{b.district?b.district+" · "+b.plot_code:"Production business"}</span></div><small className={b.status==="open"?"open":""}>{b.status==="open"?"Open":"Closed"}</small><GameIcon name="arrow" size={15}/></Link>)}</div>:<div className="pp-empty"><GameIcon name="businesses" size={28}/><h3>Every empire starts somewhere.</h3><p>No businesses registered to this player this season.</p></div>}
 {data.businesses.length>4&&<button className="pp-expand" onClick={()=>setShowAll(v=>!v)}>{showAll?"Show fewer businesses":"View businesses ("+data.businesses.length+")"}<GameIcon name="arrow" size={14}/></button>}
 {data.districts.length>0&&<div className="pp-districts"><span>District footprint</span>{data.districts.map(d=><Link href={"/districts/"+d.slug} key={d.id}><GameIcon name="pin" size={14}/>{d.name}</Link>)}</div>}
 </section>
 <section className="pp-panel pp-rankings"><header><h2><GameIcon name="respect" size={20}/>Season standings</h2><Link href="/seasons">View all <GameIcon name="arrow" size={13}/></Link></header><div className="pp-season-heading"><p className="pp-eyebrow">{data.season.status.toUpperCase()} SEASON</p><h3>{data.season.name}</h3><span>Position earned in the player economy.</span></div>
 {current.length?<RankingRows rows={current} seasonId={data.season.id}/>:<p className="pp-empty-copy">No current-season rankings yet.</p>}
 <div className="pp-previous"><h2>Previous seasons</h2>{pastSeasons.length?pastSeasons.map(id=><details key={id}><summary>{data.previous.find(r=>r.season_id===id)?.season_name}<span>Archived rankings +</span></summary><RankingRows rows={data.previous.filter(r=>r.season_id===id)}/></details>):<p>Archived rankings will appear after the first season ends.</p>}</div>
 </section></div>
 <section className="pp-details pp-panel"><div><GameIcon name="clock" size={24}/><span>Joined Blackwater<strong>{joined}</strong></span></div><div><GameIcon name="people" size={24}/><span>Gang / family<strong>{data.gang?.name??"Independent"}</strong></span></div><div><GameIcon name="respect" size={24}/><span>Level<strong>{profileNumber(data.level)} · {data.title}</strong></span></div><div className="pp-signature"><span>INFLUENCE BUILDS<br/>IN THE SHADOWS.</span><small>THE CITY REMEMBERS A NAME.</small></div></section>
 <footer className="pp-footer"><span>BLACKWATER MAFIA</span><span>SAME PLAYERS. A DIFFERENT TOMORROW.</span></footer>
 {editing&&data.is_self&&<ProfileEditor data={data} onSave={(description,description_version)=>setData(d=>({...d,description,description_version}))} onPicture={avatar_url=>setData(d=>({...d,avatar_url}))} close={()=>{setEditing(false);void refresh();}}/>}
 </div>;
}
