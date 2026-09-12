"use client";
import {useState} from "react";
import Link from "next/link";
import {GameIcon} from "@/components/game-icon";
import {useBinDiving} from "@/components/use-bin-diving";
import {loot,emptyChance,binCountdown,type BinState,type LootItem} from "@/lib/bin-diving";
import {money} from "@/lib/game";
export function LootArt({item}:{item:string}){
 const entry=loot.find(l=>l.id===item);
 return <span className={"bin-loot-art "+item} aria-hidden="true"><GameIcon name={entry?.icon??"bin"} size={34}/>{item.includes("blueprint")&&<small>{item==="pistol_blueprint"?"H.P. / 01":"H.B. / 02"}</small>}</span>;
}
export function BinDiving({initial,initialDistrict}:{initial:BinState;initialDistrict?:string}){
 const h=useBinDiving(initial),data=h.data!;
 const [selection,setSelection]=useState(initial.districts.find(d=>d.id===initialDistrict||d.slug===initialDistrict)?.id??initial.districts.find(d=>d.status!=="lockdown")?.id??"");
 const district=data.districts.find(d=>d.id===selection);
 const seconds=Math.max(0,Math.ceil(((data.ready_at?Date.parse(data.ready_at):0)-h.now)/1000));
 const playable=data.playable&&(!data.season.ends_at||Date.parse(data.season.ends_at)>h.now);
 const closed=!district||district.status==="lockdown";
 const blocked=h.busy||!playable||!data.rules.enabled||closed||seconds>0;
 const result=h.result,found=result&&loot.find(l=>l.id===result.outcome);
 return <div className="bin-page" data-feature="bin-diving-v1">
 <div className="bin-breadcrumb"><Link href="/dashboard">← Dashboard</Link><span>/</span><Link href="/districts">City map</Link><span>/ BIN DIVING</span>{data.can_manage&&<Link className="bin-owner-link" href="/owner?section=bin-diving">Owner controls ↗</Link>}</div>
 <header className="bin-hero"><div><p className="eyebrow">BLACKWATER / THE STREETS</p><h1>One man’s trash.<br/><em>Your next opportunity.</em></h1><p>Behind every empire, there’s a beginning.<br/>Work the backstreets. See what the city leaves behind.</p><span className="bin-hero-tag"><GameIcon name="bin" size={17}/> BIN DIVING</span></div></header>
 <div className="bin-strip"><span><GameIcon name="district" size={20}/><b>{data.districts.filter(d=>d.status!=="lockdown").length}</b> open districts</span><span><GameIcon name="clock" size={20}/><b>{binCountdown(data.rules.cooldown_seconds)}</b> between dives</span><span><GameIcon name="cash" size={20}/><b>{money(data.cash)}</b> your cash</span><span><GameIcon name="trophy" size={20}/>{data.season.name}</span></div>
 {h.notice&&<div className={"bin-notice"+(h.failed?" error":"")} role={h.failed?"alert":"status"}>{h.notice}{h.retry&&<button disabled={h.working} onClick={()=>void h.retryAction()}>Retry safely</button>}</div>}
 <div className="bin-layout">
 <aside className="bin-panel bin-district-panel"><header><h2>Choose your district</h2><button onClick={h.refresh} aria-label="Refresh bin diving"><GameIcon name="refresh" size={16}/></button></header><p className="bin-muted">New streets open. New places to search.</p>
 <label className="bin-mobile-select">District<select value={district?.id??""} onChange={e=>setSelection(e.target.value)}><option value="" disabled>Select a district</option>{data.districts.map(d=><option key={d.id} value={d.id}>{d.name}{d.status==="lockdown"?" · Lockdown":""}</option>)}</select></label>
 <div className="bin-district-list" aria-label="Bin diving districts">{data.districts.map(d=><button key={d.id} aria-pressed={selection===d.id} onClick={()=>setSelection(d.id)}><GameIcon name={d.status==="lockdown"?"lock":"pin"} size={20}/><span><strong>{d.name}</strong><small>{d.status==="lockdown"?"In lockdown":"Open for diving"}</small></span><span aria-hidden="true">›</span></button>)}</div>
 {!data.districts.length&&<p>No districts are open yet. Check back when the city opens its streets.</p>}
 </aside>
 <section className="bin-search-column"><div className="bin-panel bin-search"><header><h2>{district?.name??"Choose a district"}</h2><span className={"bin-status "+(!closed?"open":"")}>{!district?"NO DISTRICT":closed?"LOCKDOWN":"OPEN STREETS"}</span></header>
 <div className="bin-search-scene"><GameIcon name="bin" size={65}/><p className="eyebrow">SEARCH THE BACKSTREETS</p><h2>A little luck goes a long way.</h2><p>{district?.tagline||"Pick a district and see what someone left behind."}</p></div>
 <div className="bin-action-area"><button className="bin-gold" disabled={blocked} onClick={()=>void h.act("dive",{district_id:district?.id})}><GameIcon name={seconds?"clock":"search"} size={20}/>{h.working?"Searching…":seconds?"Next dive in "+binCountdown(seconds):"Search the bins"}<span aria-hidden="true">→</span></button>
 <p>{!playable?"Bin diving resumes when the season opens.":!data.rules.enabled?"The city Owner has paused bin diving.":closed?"Choose an open district to search.":seconds?"Catch your breath. This cooldown follows you across the city.":"Free to search. One result per dive. Luck makes no promises."}</p></div>
 </div>
 <div className={"bin-panel bin-result "+(result&&result.outcome!=="nothing"?"found":"")} role="status" aria-live="polite" aria-atomic="true"><LootArt item={result?.outcome??"nothing"}/><div><p className="eyebrow">{result?"YOUR LATEST FIND":"THE CITY KEEPS ITS SECRETS"}</p><h2>{result?result.outcome==="cash"?money(result.cash)+" in loose cash":found?.name??"Nothing this time.":"Your next find starts here."}</h2><p>{result?result.district_name+" · "+(result.outcome==="nothing"?"Try again after your cooldown.":result.outcome==="cash"?"Added to your wallet.":"Added to your stash."):"Choose a district. Search a bin. Start something."}</p></div></div>
 <section className="bin-panel bin-odds"><header><h2>What’s out there</h2><span className="bin-muted">ONE ROLL / ONE FIND</span></header><div className="bin-loot-grid">{loot.map(l=><article key={l.id}><LootArt item={l.id}/><strong>{l.name}</strong><span className="bin-chance">{data.rules[(l.id+"_chance") as keyof typeof data.rules]}%</span><p>{l.id==="cash"?money(data.rules.cash_min)+"–"+money(data.rules.cash_max)+" per find":l.description}</p></article>)}</div><p className="bin-muted">{emptyChance(data.rules)}% chance of finding nothing. Chances apply equally in every open district.</p></section>
 </section>
 <aside className="bin-panel bin-stash"><header><h2>Your street stash</h2><GameIcon name="inventory" size={19}/></header><p className="bin-muted">Finds from this season. Ready when you need them.</p>{loot.filter(l=>l.id!=="cash").map(l=><div className="bin-stash-row" key={l.id}><LootArt item={l.id}/><span><strong>{l.name}</strong><small>{l.id==="pickaxe"?"Spare equipment":"Saved for future crafting"}</small></span><b>{data.inventory[l.id as LootItem]??0}</b></div>)}
 <div className="bin-equipment"><p className="eyebrow">YOUR MINING PICKAXE</p><strong>{data.tool_condition?data.tool_condition+" condition remaining":"No pickaxe equipped"}</strong><meter aria-label="Pickaxe condition" value={data.tool_condition} min={0} max={Math.max(data.tool_max,data.tool_condition)}/><button className="bin-outline" disabled={h.busy||!playable||!(data.inventory.pickaxe??0)||data.mining_shift||data.tool_condition>=data.tool_max} onClick={()=>void h.act("equip")}>{data.tool_condition?"Replace worn pickaxe":"Equip pickaxe"} <span>→</span></button><p>{data.mining_shift?"Finish your current shift before changing equipment.":"Equipping consumes one spare. Replacing a worn tool discards its remaining condition."}</p><Link href="/districts/mines-and-quarries">Explore Mines & Quarries →</Link></div>
 <div className="bin-stash-note"><GameIcon name="shield" size={19}/><p>Blueprints stay in your stash for future crafting. Your cash and loot are saved as soon as a dive finishes.</p></div></aside>
 </div>
 <section className="bin-panel bin-history"><header><h2>Your recent dives</h2><span className="bin-muted">LATEST 30 / THIS SEASON</span></header>{data.history.length?<ol>{data.history.map(r=><li key={r.id}><LootArt item={r.outcome}/><div><strong>{r.outcome==="cash"?money(r.cash)+" found":loot.find(l=>l.id===r.outcome)?.name??"Nothing found"}</strong><span>{r.district_name}</span></div><time dateTime={r.created_at}>{new Date(r.created_at).toLocaleString()}</time></li>)}</ol>:<p className="bin-muted">Your first search will leave a story here.</p>}</section>
 </div>;
}
