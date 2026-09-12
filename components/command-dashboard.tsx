"use client";
import Link from "next/link";
import {useCallback,useEffect,useRef,useState,type ReactNode,type CSSProperties} from "react";
import {useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase/client";
import {money,rank,readyUnits,remaining} from "@/lib/game";
import {seasonPlayable} from "@/lib/seasons";
import {points,centroid,type DistrictState,type District} from "@/lib/districts";
import {atlasAreas,mailboxSummary,respectProgress,since,until,type DashboardData} from "@/lib/dashboard";
import {telegramFee} from "@/lib/telegrams";
import {PlayerAvatar} from "@/components/player-avatar";
import {GameIcon} from "./game-icon";
import {CommodityArtwork} from "@/components/commodity-artwork";
import {PanMap} from "./district-map";

function Panel({title,action,children,className=""}:{title:string;action?:ReactNode;children:ReactNode;className?:string}){
 return <section className={"command-panel "+className}><header className="command-panel-head"><h2>{title}</h2>{action}</header>{children}</section>;
}
function More({href,children="View all"}:{href:string;children?:ReactNode}){return <Link className="command-more" href={href}>{children}<GameIcon name="arrow" size={13}/></Link>;}
function Go({href,children,icon}:{href:string;children:ReactNode;icon?:string}){return <Link className="command-button" href={href}>{icon&&<GameIcon name={icon}/>}<span>{children}</span><GameIcon name="arrow" size={16}/></Link>;}
function Empty({children}:{children:ReactNode}){return <p className="command-empty">{children}</p>;}
function Meter({value,color,label}:{value:number;color?:string;label:string}){return <span className="command-meter" role="meter" aria-label={label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(value)}><i style={{width:Math.max(0,Math.min(100,value))+"%",background:color}}/></span>;}

function MarketPrices({game}:{game:DashboardData["game"]}){
 const [page,setPage]=useState(0);
 const rows=game.goods.flatMap(g=>{
  const offers=game.market.filter(o=>o.good_id===g.id&&o.status==="active"&&o.quantity>0);
  return offers.length?[{good:g,price:Math.min(...offers.map(o=>o.unit_price)),offers:offers.length}]:[];
 });
 const pages=Math.max(1,Math.ceil(rows.length/5)),current=Math.min(page,pages-1);
 useEffect(()=>setPage(p=>Math.min(p,pages-1)),[pages]);
 return <Panel title="Market Prices" className="command-market-prices" action={<More href="/market">View Market</More>}>
  <p className="command-subtitle">Live player offers · lowest ask</p>
  <div className="command-prices">{rows.slice(current*5,current*5+5).map(({good,price,offers})=><Link href={"/market?good="+encodeURIComponent(good.id)} key={good.id}><CommodityArtwork goodId={good.id} size={26}/><span>{good.name}</span><strong>{money(price)}</strong><small>{offers} {offers===1?"offer":"offers"}</small></Link>)}</div>
  {!rows.length&&<Empty>No active offers right now.</Empty>}
  {pages>1&&<nav className="command-price-pagination" aria-label="Market prices pages">
   <button type="button" aria-label="Previous market prices page" disabled={current===0} onClick={()=>setPage(current-1)}>← Previous</button>
   <span aria-live="polite" aria-atomic="true">Page {current+1} / {pages}</span>
   <button type="button" aria-label="Next market prices page" disabled={current===pages-1} onClick={()=>setPage(current+1)}>Next →</button>
  </nav>}
  <div className="command-market-note"><GameIcon name="trade" size={17}/><span>Players set the prices.<br/>Your stock creates the market.</span></div>
 </Panel>;
}

function Atlas({districts,selected}:{districts:District[];selected:string}){
 const router=useRouter();
 const extra=districts.filter(d=>!atlasAreas.some(a=>a.slug===d.slug));
 return <section className="command-atlas" aria-label="City overview">
  <div className="command-atlas-title"><h1>BLACKWATER</h1><p>A CITY OF OPPORTUNITY</p></div>
  <span className="command-atlas-motto">CONTROL TERRITORY. BUILD EMPIRES. LEAVE A LEGACY.</span>
  <PanMap label="Blackwater command map" background="/art/command-city.jpg" height={560} focus={atlasAreas.find(a=>a.slug===selected)?.label} instruction="Drag to explore · Select a district">
   {atlasAreas.map(area=>{const d=districts.find(d=>d.slug===area.slug),active=d?.slug===selected;return <g key={area.slug} className={"command-zone"+(active?" selected":"")+(d?"":" unopened")} style={{"--zone-color":area.color} as CSSProperties} role={d?"button":undefined} tabIndex={d?0:undefined} aria-label={d?"Select "+d.name:undefined} aria-pressed={d?active:undefined} onClick={()=>d&&router.push("/districts/"+d.slug)} onKeyDown={e=>{if(d&&(e.key==="Enter"||e.key===" ")){e.preventDefault();router.push("/districts/"+d.slug);}}}>
    <title>{d?d.name+" · "+(d.runtime_status??d.status):area.name+" · Unopened district"}</title><polygon points={points(area.polygon)}/>
    <foreignObject x={area.label[0]-140} y={area.label[1]-53} width="280" height="95" className="command-zone-label"><div><GameIcon name={area.icon} size={30}/><strong>{d?.name??area.name}</strong><span>{d?(d.industries.slice(0,3).join(" · ")||area.subtitle):"Unopened district"}</span></div></foreignObject>
   </g>;})}
   {extra.map(d=>{const polygon=d.city_polygon.map(([x,y])=>[x,y*560/800] as [number,number]),[x,y]=centroid(polygon);return <g key={d.id} className={"command-zone"+(selected===d.slug?" selected":"")} style={{"--zone-color":"#bda16e"} as CSSProperties} role="button" tabIndex={0} aria-label={"Select "+d.name} aria-pressed={selected===d.slug} onClick={()=>router.push("/districts/"+d.slug)} onKeyDown={e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();router.push("/districts/"+d.slug);}}}><polygon points={points(polygon)}/><text x={x} y={y} textAnchor="middle">{d.name}</text></g>;})}
  </PanMap>
  <div className="command-atlas-signature">BLACKWATER <span>COMMERCE FUELS AMBITION</span></div>
 </section>;
}

export function CommandDashboard({initial}:{initial:DashboardData}){
 const [data,setData]=useState(initial),[now,setNow]=useState(Date.parse(initial.game.server_time)),[notice,setNotice]=useState(""),[failed,setFailed]=useState(false),[busy,setBusy]=useState(false),[refreshing,setRefreshing]=useState(false),[dialog,setDialog]=useState<"jobs"|"production"|null>(null),[travel,setTravel]=useState(initial.district?.district?.slug??"");
 const modal=useRef<HTMLDialogElement>(null),travelSelect=useRef<HTMLSelectElement>(null),lock=useRef(false),loading=useRef(false),version=useRef(0),alive=useRef(true),selected=useRef(initial.district?.district?.slug??"the-waterfront"),offset=useRef(Date.parse(initial.game.server_time)-Date.now());
 const router=useRouter();
 const refresh=useCallback(async(slug=selected.current,silent=false)=>{
  if(loading.current&&slug===selected.current)return false;
  const id=++version.current;selected.current=slug;loading.current=true;setRefreshing(true);
  try{
   const client=createClient();
   const [game,city,district,season,mailbox]=await Promise.all([client.rpc("game_state"),client.rpc("city_status"),client.rpc("district_state",{p_slug:slug}),client.rpc("season_state",{p_metric:"respect"}),client.rpc("telegram_state")]);
   if(game.error||!game.data||district.error)throw new Error("The city could not be refreshed. Your last saved figures are shown.");
   if(!alive.current||id!==version.current)return false;
   offset.current=Date.parse(game.data.server_time)-Date.now();setNow(Date.parse(game.data.server_time));
   setData({game:game.data,city:city.error?null:city.data,district:district.data,season:season.error?null:season.data,mailbox:mailbox.error||!mailbox.data?null:mailboxSummary(mailbox.data)});
   setTravel(district.data?.district?.slug??slug);setFailed(false);if(!silent)setNotice("");
   window.dispatchEvent(new Event("blackwater:game"));return true;
  }catch(error){if(alive.current&&id===version.current){setFailed(true);setNotice(error instanceof Error?error.message:"Could not refresh the city.");}return false;}
  finally{if(id===version.current){loading.current=false;if(alive.current)setRefreshing(false);}}
 },[]);
 useEffect(()=>{
  alive.current=true;
  const timer=setInterval(()=>setNow(Date.now()+offset.current),1000);
  const poll=setInterval(()=>{if(!document.hidden&&!lock.current)void refresh(selected.current,true);},30000);
  const visible=()=>{if(!document.hidden&&!lock.current)void refresh(selected.current,true);};
  document.addEventListener("visibilitychange",visible);
  return()=>{alive.current=false;++version.current;loading.current=false;clearInterval(timer);clearInterval(poll);document.removeEventListener("visibilitychange",visible);};
 },[refresh]);
 useEffect(()=>{
  const frame=requestAnimationFrame(()=>window.dispatchEvent(new CustomEvent("blackwater:dashboard",{detail:{stock:data.game.inventory.reduce((s,g)=>s+g.quantity,0),unread:data.mailbox?.unread??null}})));return()=>cancelAnimationFrame(frame);
 },[data]);
 useEffect(()=>{if(dialog&&!modal.current?.open)modal.current?.showModal();else if(!dialog)modal.current?.close();},[dialog]);
 const game=data.game,ds=data.district,d=ds?.district,player=data.city?.player;
 const playerRank=player?.rank??rank(game.player.xp,game.settings),progress=respectProgress(game.player.xp,game.settings),stock=game.inventory.reduce((n,i)=>n+i.quantity,0);
 const playing=seasonPlayable(game.season,now),cooldown=remaining(game.player.job_ready_at,now);
 const districtPath=d?"/districts/"+d.slug:"/districts";
 const influenceTotal=(ds?.territory.neutral_influence??0)+(ds?.influence.reduce((sum,g)=>sum+g.influence,0)??0);
 const ownInfluence=ds?.influence.find(g=>g.gang_id===ds.gang_id)?.influence??0,neutral=ds?.territory.neutral_influence??0;
 const share=(value:number)=>influenceTotal?value/influenceTotal*100:0;
 const available=ds?.districts.reduce((n,d)=>n+(d.available_plots??0),0)??0;
 const telegramOnline=!!data.mailbox?.office.available&&data.mailbox.office.status==="open";

 const activity=[...game.events.map(e=>({...e,key:"player-"+e.id,icon:e.cash_delta?"cash":"people",href:"/ledger"})),...(ds?.events??[]).map(e=>({...e,key:"district-"+e.id,cash_delta:0,icon:e.category==="business"?"production":e.category==="property"?"property":e.category==="gang"?"shield":"ledger",href:e.plot_id?districtPath+"?tab=Plots&plot="+e.plot_id:districtPath+"?tab=Activity"}))].sort((a,b)=>Date.parse(b.created_at)-Date.parse(a.created_at)).slice(0,5);
 const work=ds?.buildings.filter(b=>b.owner_id===game.player.id&&b.construction_status==="building")??[];
 const productionTime=playing?now:Date.parse(game.season.locked_at||game.season.ends_at||game.server_time);
 const upcoming=[...work.map(b=>({key:b.id,name:(ds?.building_types.find(t=>t.id===b.building_type)?.name??"Building")+" construction",detail:"Your property · "+(ds?.plots.find(p=>p.id===b.plot_id)?.code??""),when:b.ready_at,icon:"production",href:districtPath+"?tab=Plots&plot="+b.plot_id})),...(ds?.auctions??[]).map(a=>({key:a.id,name:"Property auction",detail:"Plot "+ds?.plots.find(p=>p.id===a.plot_id)?.code,when:a.ends_at,icon:"auction",href:districtPath+"?tab=Plots&plot="+a.plot_id})),...(game.season.ends_at?[{key:"season",name:"Season closes",detail:game.season.name,when:game.season.ends_at,icon:"trophy",href:"/seasons"}]:[])].sort((a,b)=>Date.parse(a.when)-Date.parse(b.when)).slice(0,4);
 async function act(action:string,payload:Record<string,string>){
  if(lock.current||refreshing)return;lock.current=true;setBusy(true);setNotice("");setFailed(false);
  try{
   const {data:result,error}=await createClient().rpc("game_action",{p_action:action,p_payload:{...payload,season_id:game.season.id}});
   if(error||result?.error)throw new Error(result?.error??"Could not confirm the action. Refresh before trying again.");
   const fresh=await refresh(selected.current,true);setNotice((result.message??"Action completed.")+(fresh?"":" Refresh city to see your updated totals."));
  }catch(error){setFailed(true);setNotice(error instanceof Error?error.message:"Could not complete this action.");}
  finally{lock.current=false;setBusy(false);}
 }

 const change=()=>{travelSelect.current?.scrollIntoView({behavior:"smooth",block:"center"});travelSelect.current?.focus();};
 return <div className="command-dashboard">
  {notice&&<div className={"command-notice"+(failed?" error":"")} role={failed?"alert":"status"}>{notice}<button aria-label="Dismiss dashboard message" onClick={()=>setNotice("")}>×</button></div>}
  {!playing&&<div className="command-notice">This season is {game.season.status}. Your empire remains available to view.</div>}
  <aside className="command-player command-panel" aria-label="Your empire">
   <Link href="/profile" className="command-portrait-link" aria-label="View your player profile"><PlayerAvatar className="command-portrait" src={data.city?.avatar_url} name={data.game.player.handle} size={512}/></Link>
   <div className="command-player-name"><h2>{data.city?.username??game.player.handle}</h2><Link href="/account" aria-label="Edit account"><GameIcon name="edit" size={15}/></Link></div>
   <p className="command-player-rank"><GameIcon name="shield" size={15}/>{playerRank}</p><p className="command-player-quote">“Power moves people.”</p>
   <div className="command-level"><div><span>Lv. {player?.level??"—"}</span><small>{game.player.xp.toLocaleString("en-US")} {progress.next?"/ "+progress.next.value.toLocaleString("en-US"):""} respect</small></div><Meter value={progress.percent} label="Progress to next respect rank"/><small>{progress.next?"Next rank: "+progress.next.name:"Highest configured rank"}</small></div>
   <dl className="command-player-stats">
    <div><dt><GameIcon name="coins"/>Cash</dt><dd>{money(game.player.cash)}</dd></div>
    
    <div><dt><GameIcon name="inventory"/>Stock</dt><dd>{stock.toLocaleString("en-US")} <small>units</small></dd></div>
    <div><dt><GameIcon name="bolt"/>Operations</dt><dd><span className={cooldown?"":"command-green"}>{cooldown?until(game.player.job_ready_at,now):playing?"Ready":"Paused"}</span></dd></div>
    <div><dt><GameIcon name="flame"/>District heat</dt><dd>{d?<><Meter value={d.police_heat} label="District police heat" color="#b26050"/><small>{d.police_heat} / 100</small></>:"—"}</dd></div>
   </dl>
   <div className="command-location"><GameIcon name="pin" size={23}/><span>Viewing district</span><strong>{d?.name??"City map"}<small>Blackwater</small></strong></div>
   <div className="command-quick"><h3>QUICK ACTIONS</h3>
    <button className="command-button" onClick={()=>setDialog("jobs")}><GameIcon name="operations"/><span>Plan an Operation</span><GameIcon name="arrow" size={16}/></button>
    <Go href="/districts/mines-and-quarries" icon="pickaxe">Explore Resources</Go><Go href="/bin-diving" icon="bin">Bin Diving</Go><Go href="/refineries" icon="production">Refineries</Go>
    <button className="command-button" onClick={()=>setDialog("production")}><GameIcon name="tools"/><span>Production</span><GameIcon name="arrow" size={16}/></button>
    <button className="command-button" onClick={()=>setDialog("jobs")}><GameIcon name="briefcase"/><span>Find a Job</span><GameIcon name="arrow" size={16}/></button>
   </div>
   <div className="command-player-art"><img src="/art/harbor-small.webp" alt="" width={640} height={360}/><p>Every fortune<br/>has a dark side.</p></div>
   <p className="command-player-signature">BLACKWATER <small>A PLAYER-DRIVEN CRIME ECONOMY</small></p>
  </aside>
  <div className="command-center">
   <Atlas districts={ds?.districts??[]} selected={d?.slug??""}/>
   <div className="command-summary-grid">
    <Panel title="Territory Control" className="command-territory">
     <p className="command-subtitle">{d?.name??"District unavailable"} · {ds?.influence.length??0} gangs</p>
     <div className="command-control-bar" aria-label="District territory shares"><i style={{width:share(ownInfluence)+"%",background:"#4e8967"}}/><i style={{width:share(Math.max(0,influenceTotal-ownInfluence-neutral))+"%",background:"#a76654"}}/><i style={{width:(influenceTotal?share(neutral):100)+"%",background:"#666b65"}}/></div>
     <div className="command-control-key"><span><i/>Your gang {share(ownInfluence).toFixed(0)}%</span><span><i/>Rivals {share(Math.max(0,influenceTotal-ownInfluence-neutral)).toFixed(0)}%</span><span><i/>Neutral {influenceTotal?share(neutral).toFixed(0):"—"}%</span></div>
     <Go href={districtPath+"?tab=Territory"}>View Details</Go>
    </Panel>
    <Panel title="Quick Travel" className="command-travel"><p className="command-subtitle">Explore an open district</p><label className="sr-only" htmlFor="command-travel">Select district</label><select id="command-travel" ref={travelSelect} value={travel} onChange={e=>setTravel(e.target.value)}>{!ds?.districts.length&&<option value="">No open districts</option>}{ds?.districts.map(d=><option key={d.id} value={d.slug}>{d.name}</option>)}</select><button className="command-button" disabled={!travel} onClick={()=>router.push("/districts/"+travel)}><GameIcon name="pin"/><span>Travel</span><GameIcon name="arrow" size={16}/></button></Panel>
    <Panel title="Available Plots" className="command-land"><p className="command-subtitle">Build your empire</p><div><img src="/art/exchange-small.webp" alt="Blackwater real estate" width={320} height={360}/><p><strong>{available}</strong> available plots<small>across {ds?.districts.length??0} open districts</small><More href={districtPath+"?tab=Plots"}>View Plots</More></p></div></Panel>
    <Panel title="Strategic Properties" className="command-sites"><p className="command-subtitle">High-value opportunities</p>{ds?.sites.filter(s=>s.kind==="strategic").slice(0,3).map(s=><Link key={s.id} className="command-site" href={districtPath+(s.plot_id?"?tab=Plots&plot="+s.plot_id:"?tab=Territory")}><GameIcon name={s.resource_type==="harbor"?"anchor":"property"}/><span>{s.name}<small>{s.data.description}</small></span><GameIcon name="arrow" size={14}/></Link>)}{data.mailbox&&<Link className="command-site" href={"/districts/"+data.mailbox.office.district_slug+"?tab=Plots&plot="+data.mailbox.office.plot_id}><GameIcon name="mail"/><span>City Telegram Office<small>Earn fees from city-wide messages</small></span><GameIcon name="arrow" size={14}/></Link>}{!ds&&<Empty>District records unavailable.</Empty>}</Panel>
   </div>
   <div className="command-economy-grid">
    <Panel title="Recent Activity" action={<More href={districtPath+"?tab=Activity"}/>}>
     <ol className="command-activity">{activity.map(e=><li key={e.key}><time dateTime={e.created_at}>{since(e.created_at,now)}</time><GameIcon name={e.icon} size={15}/><Link href={e.href}>{e.description}</Link>{e.cash_delta!==0&&<strong className={e.cash_delta>0?"command-green":"command-red"}>{e.cash_delta>0?"+":"−"}{money(Math.abs(e.cash_delta))}</strong>}</li>)}</ol>{!activity.length&&<Empty>Your first move starts the story.</Empty>}
    </Panel>
    <MarketPrices game={game}/>
    <Panel title="Production Queue" action={<button className="command-more" onClick={()=>setDialog("production")}>Manage</button>}><div className="command-production">{game.businesses.slice(0,2).map(b=>{const g=game.goods.find(g=>g.id===b.good_id);if(!g)return null;const units=readyUnits(b,g,productionTime,game.settings.offline_batches);return <div key={b.good_id}><CommodityArtwork goodId={g.id} size={28}/><span>{g.name}<small>{g.business_name}</small></span><button disabled={busy||!playing||!units} onClick={()=>act("collect",{good_id:g.id})}>{units?units+" ready":playing?until(new Date(Date.parse(b.collected_at)+g.cycle_seconds*1000).toISOString(),now):"Paused"}</button></div>;})}{work.slice(0,2).map(b=><Link className="command-construction" href={districtPath+"?tab=Plots&plot="+b.plot_id} key={b.id}><GameIcon name="tools"/><span>Construction<small>Plot {ds?.plots.find(p=>p.id===b.plot_id)?.code}</small></span><small>{until(b.ready_at,now)}</small></Link>)}</div>{!game.businesses.length&&!work.length&&<Empty>No production running.<br/>Establish a business to supply the city.</Empty>}<button className="command-queue-button" onClick={()=>setDialog("production")}>+ Manage Production</button><Link className="command-queue-button" href={districtPath+"?tab=Plots"}>+ Build on Your Land</Link></Panel>
    <Panel title="Upcoming Events" action={<More href={districtPath+"?tab=Activity"}/>}><div className="command-upcoming">{upcoming.map(e=><Link key={e.key} href={e.href}><time dateTime={e.when}>{until(e.when,now)}</time><GameIcon name={e.icon}/><span>{e.name}<small>{e.detail}</small></span></Link>)}</div>{!upcoming.length&&<Empty>No scheduled events.<br/>Auctions, construction and season deadlines appear here.</Empty>}<button className="command-sync" disabled={refreshing||busy} onClick={()=>void refresh()}><GameIcon name="refresh" size={13}/>{refreshing?"Refreshing…":"Refresh city"}</button></Panel>
   </div>
  </div>
  <aside className="command-right" aria-label="City intelligence">
   <Panel title={"District: "+(d?.name??"Unavailable")} action={<button className="command-more command-change" onClick={change}>Change</button>} className="command-dossier">{d?<><img src={d.image_url} alt={d.name+" skyline"} width={720} height={280}/><p>{d.description}</p><dl className="command-district-facts"><div><dt><GameIcon name="shield" size={15}/>Control</dt><dd>{ds?.territory.controller_name??d.controller??"Neutral"}</dd></div><div><dt><GameIcon name="respect" size={15}/>Your influence</dt><dd><Meter value={share(ownInfluence)} label="Your gang influence"/><small>{share(ownInfluence).toFixed(0)}%</small></dd></div><div><dt><GameIcon name="property" size={15}/>Plots</dt><dd>{d.available_plots??ds?.plots.filter(p=>p.status==="available").length??0} available</dd></div><div><dt><GameIcon name="production" size={15}/>Businesses</dt><dd>{d.active_businesses??ds?.businesses.filter(b=>b.status==="open").length??0} active</dd></div></dl><Go href={districtPath}>View District</Go></>:<Empty>District information is unavailable. Use Refresh city to reconnect.</Empty>}</Panel>
   <Panel title="Telegram Office" action={<span className={"command-office-status"+(telegramOnline?" online":"")}>{data.mailbox?(telegramOnline?"Online":"Closed")+" · "+telegramFee(data.mailbox.office.fee):"Unavailable"}</span>} className="command-telegram"><img src="/art/telegram-office.jpg" alt="Blackwater Telegram Office" width={720} height={220}/><p>The city’s lifeline. Trade, form alliances, plan operations.</p><Go href="/telegrams">Open Telegrams {data.mailbox?.unread?<b className="command-unread">{data.mailbox.unread}</b>:null}</Go></Panel>
   <Panel title="Gang Influence" action={<More href={districtPath+"?tab=Territory"}/>} className="command-gangs"><ol>{ds?.influence.slice(0,6).map((g,i)=><li key={g.gang_id}><span>{i+1}</span><GameIcon name="people" size={16}/><Link href={districtPath+"?tab=Territory"}>{g.name}</Link><strong>{share(g.influence).toFixed(0)}%</strong><Meter value={share(g.influence)} label={g.name+" influence"} color={["#9577b2","#a56858","#5699aa","#619278","#bc9d63","#9b9990"][i]}/></li>)}</ol>{!ds?.influence.length&&<div className="command-neutral"><GameIcon name="shield" size={30}/><strong>Neutral territory</strong><p>No gang has established influence.<br/>Make your first move.</p><More href={districtPath+"?tab=Territory"}>Establish your crew</More></div>}</Panel>
   <Panel title={game.season.name} action={<span className="command-season-end">{game.season.ends_at?"Ends in "+until(game.season.ends_at,now):game.season.status}</span>} className="command-season"><div className="command-standing"><div><strong>{data.season?.my_rank?"#"+data.season.my_rank.rank:"—"}</strong><span>Your {data.season?.metric==="respect"?"respect":"season"} rank</span></div><div><GameIcon name="trophy" size={27}/><strong>{game.player.xp.toLocaleString("en-US")}</strong><span>Season Respect</span></div></div><Go href="/seasons?view=rankings">View Leaderboard</Go></Panel>
  </aside>
  {dialog&&<dialog ref={modal} className="command-modal" aria-labelledby="command-modal-title" onCancel={e=>{if(busy)e.preventDefault();else setDialog(null);}}><header><div><p className="eyebrow">YOUR NEXT MOVE</p><h2 id="command-modal-title">{dialog==="jobs"?"Work the city":"Your production network"}</h2></div><button disabled={busy} aria-label="Close actions" onClick={()=>setDialog(null)}>×</button></header>{notice&&<p className={"command-notice"+(failed?" error":"")} role={failed?"alert":"status"}>{notice}</p>}
   {dialog==="jobs"?<><p>Earn cash and respect. Every completed operation is recorded.</p>{game.jobs.map(j=><article className="command-job" key={j.id}><GameIcon name="briefcase" size={25}/><div><h3>{j.name}</h3><p>{j.description}</p><small>{money(j.reward)} · +{j.xp} respect · {Math.ceil(j.cooldown/60)} min cooldown</small></div><button className="command-button" disabled={busy||refreshing||!playing||cooldown>0} onClick={()=>act("job",{job:j.id})}>{cooldown?until(game.player.job_ready_at,now):"Start operation"}<GameIcon name="arrow" size={15}/></button></article>)}{!game.jobs.length&&<Empty>No jobs are available this season.</Empty>}</>:<><p>Build supply for the player market. Acquisition costs and production rates are set by the city.</p>{game.goods.filter(g=>g.business_available!==false).map(g=>{const owned=game.businesses.find(b=>b.good_id===g.id),units=owned?readyUnits(owned,g,productionTime,game.settings.offline_batches):0;return <article className="command-job" key={g.id}><GameIcon name="production" size={25}/><div><h3>{g.business_name}</h3><p>{g.batch_size} {g.name.toLowerCase()} every {Math.ceil(g.cycle_seconds/60)} min</p><small>{owned?units+" units ready":money(g.business_cost)+" acquisition"}</small></div><button className="command-button" disabled={busy||refreshing||!playing||(owned?!units:game.player.cash<g.business_cost)} onClick={()=>act(owned?"collect":"business",{good_id:g.id})}>{owned?"Collect "+units+" units":"Buy · "+money(g.business_cost)}</button></article>;})}<Go href={districtPath+"?tab=Plots"}>Develop your district properties</Go></>}
  </dialog>}
 </div>;
}
