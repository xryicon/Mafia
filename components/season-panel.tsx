"use client";
import {useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase/client";
import {ActionForm} from "@/components/staff-panel";
import {resetConfirmation,type Ranking,type SeasonState} from "@/lib/seasons";
const hidden=(name:string,value:string)=>({name,label:name,type:"hidden",value});
const toggle=[{value:"true",label:"Yes"},{value:"false",label:"No"}];
function Rankings({rows}:{rows:Ranking[]}){return rows.length?<div className="table-scroll"><table className="market-table"><thead><tr><th>Rank</th><th>Player</th><th>Score</th></tr></thead><tbody>{rows.map(r=><tr key={r.player_id}><td className="gold">#{r.rank}</td><td><Link href={"/players/"+r.player_id}>{r.handle}</Link></td><td>{Number(r.score).toLocaleString("en-US")}</td></tr>)}</tbody></table></div>:<p className="panel-empty">No rankings recorded for this category yet.</p>;}
export function SeasonPanel({initial}:{initial:SeasonState}){
 const [data,setData]=useState(initial),[notice,setNotice]=useState(""),[loading,setLoading]=useState(false),[failed,setFailed]=useState(false),[tab,setTab]=useState<"rankings"|"hall"|"manage">("rankings");
 async function load(season=data.season.id,metric=data.metric,offset=0){
  const {data:next,error}=await createClient().rpc("season_state",{p_season:season,p_metric:metric,p_offset:offset});
  if(error)throw new Error(error.message);setData(next);
 }
 async function view(season:string,metric:string,offset=0){setLoading(true);try{await load(season,metric,offset);}catch{setFailed(true);setNotice("Could not load rankings. Please retry.");}finally{setLoading(false);}}
 async function send(action:string,payload:Record<string,string>){
  setFailed(false);setNotice("");
  try{const {data:result,error}=await createClient().rpc("season_action",{action,payload});
   if(error||result?.error)throw new Error(result?.error||error?.message);setNotice(result.message);
   await load(result.season_id||data.season.id,data.metric,0);
  }catch(e){setFailed(true);setNotice(e instanceof Error?e.message:"Season action failed.");}
 }
 const s=data.season,current=data.seasons.find(s=>s.id===data.current_season_id)!;
 const frozen=["finalized","archived"].includes(s.status),board=data.boards.find(b=>b.metric===data.metric);
 const mutable=!frozen,selectedCurrent=s.id===current.id;
 return <main className="control-layout"><div className="control-heading"><div><p className="eyebrow">BLACKWATER / SEASONS</p><h1>A place in history.</h1><p>Build your empire. Leave your name on the city.</p></div><Link className="button ghost" href="/dashboard">Return to empire</Link></div>
 <section className="season-banner"><div><span className="tag">{s.status.toUpperCase()}{selectedCurrent?" · CURRENT":""}</span><h2>{s.name}</h2><p>{s.ends_at?"Ends "+new Date(s.ends_at).toLocaleString():"No scheduled end"} · {frozen?"Final results preserved":"Rankings update as players act"}</p></div><label>Choose season<select aria-label="Choose season" value={s.id} disabled={loading} onChange={e=>view(e.target.value,data.metric)}>{data.seasons.map(s=><option key={s.id} value={s.id}>{s.name} · {s.status}</option>)}</select></label></section>
 <nav className="market-filters season-tabs" aria-label="Season views"><button className={tab==="rankings"?"selected":""} onClick={()=>setTab("rankings")}>Leaderboards</button><button className={tab==="hall"?"selected":""} onClick={()=>{setTab("hall");view(s.id,data.metric,0);}}>Hall of Fame</button>{data.can_manage&&<button className={tab==="manage"?"selected":""} onClick={()=>setTab("manage")}>Owner controls</button>}</nav>
 {notice&&<p className={"game-notice "+(failed?"error":"")} role={failed?"alert":"status"}>{notice}</p>}
 {tab==="rankings"&&<section className="game-panel"><div className="panel-heading"><div><p className="eyebrow">{frozen?"ARCHIVED SCORES":"SEASON STANDINGS"}</p><h2>{board?.label||"Leaderboard"}</h2></div><button className="button small ghost" disabled={loading} onClick={()=>view(s.id,data.metric,data.offset)}>Refresh</button></div>
 <div className="market-filters">{data.boards.filter(b=>b.enabled).map(b=><button key={b.metric} className={b.metric===data.metric?"selected":""} onClick={()=>view(s.id,b.metric)}>{b.label}</button>)}</div>
 <p className="panel-empty">{board?.description}{board&&!board.available&&" This gameplay system is not available yet; only server-recorded activity will count."} Equal scores share a rank.</p>
 {data.my_rank&&<p className="season-personal">Your position: <strong>#{data.my_rank.rank}</strong> · {Number(data.my_rank.score).toLocaleString("en-US")}</p>}
 <Rankings rows={data.rankings}/>
 <div className="panel-heading"><button className="button small ghost" disabled={loading||data.offset===0} onClick={()=>view(s.id,data.metric,Math.max(0,data.offset-100))}>Previous</button><span>{data.total} players</span><button className="button small ghost" disabled={loading||data.offset+100>=data.total} onClick={()=>view(s.id,data.metric,data.offset+100)}>Next</button></div></section>}
 {tab==="hall"&&<section><h2>Hall of Fame</h2><p>Champions from archived seasons. Shared ranks earn the same recognition.</p><div className="control-grid">{data.hall_of_fame.map(r=><article className="control-card hall-card" key={String(r.season_id)+String(r.metric)+r.player_id}><p className="eyebrow">{r.season_name}</p><strong className="hall-place">#{r.rank}</strong><h3><Link href={"/players/"+r.player_id}>{r.handle}</Link></h3><p>{r.label} · {Number(r.score).toLocaleString("en-US")}</p></article>)}</div>{!data.hall_total&&<p className="control-card">The first champions will appear after a season is finalized and archived.</p>}<div className="panel-heading"><button className="button small ghost" disabled={loading||data.offset===0} onClick={()=>view(s.id,data.metric,Math.max(0,data.offset-100))}>Previous champions</button><button className="button small ghost" disabled={loading||data.offset+100>=data.hall_total} onClick={()=>view(s.id,data.metric,data.offset+100)}>More champions</button></div></section>}
 {tab==="manage"&&data.can_manage&&<>
 <section><h2>Season lifecycle</h2><p>Lock → snapshot final results → archive → reset into a draft or launch the next season. Accounts, subscriptions, bans and moderation history are retained.</p>
 <div className="control-grid"><ActionForm title="Create season" action="create" send={send} fields={[{name:"name",label:"Season name"}]}/>
 {selectedCurrent&&s.status==="open"&&<ActionForm title="Lock season" action="lock" send={send} fields={[hidden("season_id",s.id)]}/>}
 {selectedCurrent&&s.status==="locked"&&<><ActionForm title="Reopen season" action="open" send={send} fields={[hidden("season_id",s.id)]}/><ActionForm title="Snapshot final results" action="snapshot" send={send} fields={[hidden("season_id",s.id)]}/></>}
 {s.status==="finalized"&&<ActionForm title="Archive leaderboards" action="archive" send={send} fields={[hidden("season_id",s.id)]}/>}
 {selectedCurrent&&s.status==="draft"&&<ActionForm title="Open prepared season" action="launch" send={send} fields={[hidden("season_id",s.id)]}/>}
 </div></section>
 {s.status==="draft"&&!selectedCurrent&&data.can_reset&&<section className="reset-zone"><h2>Start fresh in {s.name}</h2><p>This closes old wallets and starts fresh money, inventory, skills, levels, assets, gangs, loans, queues, orders and seasonal stats. Old season records and rankings remain preserved.</p>{current.status!=="archived"?<p>First select and archive the current season: {current.name}.</p>:<div className="control-grid">{["reset","launch_next"].map(action=><ActionForm key={action} title={action==="reset"?"Prepare gameplay reset":"Reset and launch next season"} action={action} send={send} fields={[hidden("season_id",s.id),hidden("expected_current_season",current.id),{name:"confirmation",label:"Type "+resetConfirmation(current.name)+" to confirm"}]}/>)}</div>}</section>}
 {mutable&&!(selectedCurrent&&s.status==="draft")&&<section><h2>Configure this season</h2><ActionForm key={s.id+"config"+s.status} title="Season configuration" action="configure" send={send} fields={[hidden("season_id",s.id),{name:"name",label:"Season name",value:s.name},...(s.status==="draft"?[{name:"starting_cash",label:"Starting cash",type:"number",min:0,max:100000000,value:s.starting_cash},{name:"starting_crates",label:"Starting whiskey crates",type:"number",min:0,max:1000,value:s.starting_crates}]:[]),{name:"starts_at",label:"Start time (UTC ISO timestamp, or leave blank)",type:"optional",value:s.starts_at||""},{name:"ends_at",label:"End time (UTC ISO timestamp, or leave blank)",type:"optional",value:s.ends_at||""},{name:"hall_of_fame_places",label:"Hall of Fame ranks per category",type:"number",min:0,max:100,value:s.hall_of_fame_places}]}/></section>}
 <section><h2>Leaderboard configuration</h2><p>Metrics come from server records. Categories for systems not yet built are disabled by default.</p><div className="control-grid">{data.boards.map(b=><details className="control-card" key={s.id+b.metric}><summary>{b.label} · {b.enabled?"Enabled":"Disabled"}{!b.available?" · Future system":""}</summary><p>{b.description}</p>{mutable&&<ActionForm title={b.label+" leaderboard"} action="leaderboard" send={send} fields={[hidden("season_id",s.id),hidden("metric",b.metric),{name:"label",label:"Display name",value:b.label},{name:"enabled",label:"Enabled",value:String(b.enabled),options:toggle},{name:"direction",label:"Sort direction",value:b.direction,options:[{value:"desc",label:"Highest first"},{value:"asc",label:"Lowest first"}]},{name:"include_banned",label:"Include banned players",value:String(b.include_banned),options:toggle},{name:"hall_of_fame",label:"Award Hall of Fame places",value:String(b.hall_of_fame),options:toggle}]}/>}</details>)}</div></section>
 <section><h2>Inventory book values</h2><p>Net worth values stock and escrow using these values, never a player's asking price.</p><div className="control-grid">{data.valuations.map(v=>mutable?<ActionForm key={s.id+v.good_id} title={v.good_id+" valuation"} action="valuation" send={send} fields={[hidden("season_id",s.id),hidden("good_id",v.good_id),{name:"unit_value",label:"Value per unit",type:"number",min:0,max:100000000,value:v.unit_value}]}/>:<p className="control-card" key={v.good_id}>{v.good_id}: {v.unit_value}</p>)}</div></section>
 </>}
 </main>;
}
