"use client";
import {StreetOperationsPanel} from "./street-operations-panel";
import {useState} from "react";

import "./street-operations.css";
import {ScavengingChoices} from "./scavenging-choices";
import "./scavenging-choices.css";
import Link from "next/link";
import {CommodityArtwork} from "@/components/commodity-artwork";
import {GameIcon} from "@/components/game-icon";
import {useBinDiving} from "@/components/use-bin-diving";
import {loot,emptyChance,binCountdown,type BinState,type LootItem} from "@/lib/bin-diving";
import {money} from "@/lib/game";
export function LootArt({item}:{item:string}){
 if(["pickaxe","pistol_blueprint","bullet_blueprint","bandages_blueprint"].includes(item))return <span className={"bin-loot-art illustrated "+item}><CommodityArtwork goodId={item} size={96}/></span>;
 const entry=loot.find(l=>l.id===item);
 return <span className={"bin-loot-art "+item} aria-hidden="true"><GameIcon name={entry?.icon??"bin"} size={34}/>{item.includes("blueprint")&&<small>{item==="pistol_blueprint"?"H.P. / 01":"H.B. / 02"}</small>}</span>;
}
export function BinDiving({initial,initialDistrict}:{initial:BinState;initialDistrict?:string}){
 const h=useBinDiving(initial),data=h.data!;
 const [selection,setSelection]=useState(initial.districts.find(d=>d.id===initialDistrict||d.slug===initialDistrict)?.id??initial.scavenging?.session?.district_id??initial.districts.find(d=>d.status!=="lockdown")?.id??"");
 const district=data.districts.find(d=>d.id===selection);
 const seconds=Math.max(0,Math.ceil(((data.ready_at?Date.parse(data.ready_at):0)-h.now)/1000));
 const playable=data.playable&&(!data.season.ends_at||Date.parse(data.season.ends_at)>h.now);
 const closed=!district||district.status==="lockdown";
  const result=h.result,found=result&&loot.find(l=>l.id===result.outcome);
 return <div className="bin-page street-operations-page">
 <div className="bin-breadcrumb"><Link href="/dashboard">← Dashboard</Link><span>/</span><Link href="/districts">City districts</Link><span>/ SCAVENGING</span>{data.can_manage&&<Link className="bin-owner-link" href="/owner?section=bin-diving">Owner controls ↗</Link>}</div>
 <header className="street-hero"><div><p className="eyebrow">BLACKWATER / AFTER DARK</p><h1 aria-label="Scavenging">The streets<br/><em>have a price.</em></h1><p>Choose a district, search a bin or lockpick a car, and collect your finds. Watch the police risk.</p><div className="street-hero-tags"><span>SCAVENGE</span><span>STEAL</span><span>ESCAPE</span></div></div><span className="street-hero-motto">FORTUNE FAVOURS<br/>THE WATCHFUL.</span></header>
 <div className="street-district-bar"><label>Operating district<select aria-label="District" disabled={!!data.scavenging?.operations?.pursuit||!!data.scavenging?.session?.pending} value={district?.id??""} onChange={e=>setSelection(e.target.value)}><option value="" disabled>Select a district</option>{data.districts.map(d=><option key={d.id} value={d.id}>{d.name}{d.slug==="blackwater-island"?" · High risk":d.status==="lockdown"?" · Lockdown":""}</option>)}</select></label><div className="street-wallet"><span>ON HAND</span><strong>{money(data.cash)}</strong></div><button className="bin-outline" onClick={h.refresh} aria-label="Refresh bin diving"><GameIcon name="refresh" size={18}/>Refresh</button></div>
 {h.notice&&<div className={"bin-notice"+(h.failed?" error":"")} role={h.failed?"alert":"status"}>{h.notice}{h.retry&&<button disabled={h.working} onClick={()=>void h.retryAction()}>Retry safely</button>}</div>}
 {district?.slug==="blackwater-island"&&<p className="street-island-warning"><GameIcon name="shield" size={21}/>Prison island: increased patrols, longer sentences and higher cash rewards. Plan your escape before taking a risk.</p>}
 <ScavengingChoices state={data.scavenging} district={district} now={h.now} busy={h.busy} blocked={!playable||!data.rules.enabled||closed} cooldown={seconds} lockpicks={data.inventory.lockpick??0} act={h.act}/>
 <details className="street-loot-guide" open><summary>Vehicles, police risk & street record</summary><StreetOperationsPanel ops={data.scavenging?.operations} busy={h.busy} act={h.act}/></details>
 <section className={"bin-panel bin-result "+(result&&result.outcome!=="nothing"?"found":"")} role="status" aria-live="polite"><LootArt item={result?.outcome??"nothing"}/><div><p className="eyebrow">LATEST FIND</p><h2>{result?result.outcome==="cash"?money(result.cash)+" in loose cash":found?.name??"Nothing this time.":"Every street has a story."}</h2><p>{result?result.district_name+" · "+(result.outcome==="cash"?"Added to your wallet.":"Check Inventory for your finds."):"Search bins and cars, investigate marked events or attempt a vehicle theft."}</p></div></section>
 <details className="street-loot-guide" open><summary>Loot guide & current chances <span>Owner-configured</span></summary><section className="bin-panel bin-odds"><div className="bin-loot-grid">{loot.map(l=><article key={l.id}><LootArt item={l.id}/><strong>{l.name}</strong><span className="bin-chance">{data.rules[(l.id+"_chance") as keyof typeof data.rules]}%</span><p>{l.id==="cash"?money(data.rules.cash_min)+"–"+money(data.rules.cash_max)+" base reward":l.description}</p></article>)}</div><p className="bin-muted">{emptyChance(data.rules)}% chance of finding nothing. Base item chances stay the same across districts. Blackwater Island and street events multiply cash finds. <Link href="/inventory">Manage your inventory →</Link></p></section></details>
<details className="street-loot-guide" open><summary>Equipment & recent finds</summary><div className="street-support"> <aside className="bin-panel bin-stash"><header><h2>Your street stash</h2><GameIcon name="inventory" size={19}/></header><p className="bin-muted">Finds from this season. Ready when you need them.</p>{loot.filter(l=>l.id!=="cash").map(l=><div className="bin-stash-row" key={l.id}><LootArt item={l.id}/><span><strong>{l.name}</strong><small>{l.id==="pickaxe"?"Spare equipment":l.id==="lockpick"?"Single-use lockpick":"Trade or save for crafting"}</small></span><b>{data.inventory[l.id as LootItem]??0}</b><Link className="bin-trade-link" aria-label={"Trade "+l.name} href={"/market?view=inventory&good="+l.id}>Trade ↗</Link></div>)}
 <div className="bin-equipment"><p className="eyebrow">YOUR MINING PICKAXE</p><strong>{data.tool_condition?data.tool_condition+" condition remaining":"No pickaxe equipped"}</strong><meter aria-label="Pickaxe condition" value={data.tool_condition} min={0} max={Math.max(data.tool_max,data.tool_condition)}/><button className="bin-outline" disabled={h.busy||!playable||!(data.inventory.pickaxe??0)||data.mining_shift||data.tool_condition>=data.tool_max} onClick={()=>void h.act("equip")}>{data.tool_condition?"Replace worn pickaxe":"Equip pickaxe"} <span>→</span></button><p>{data.mining_shift?"Finish your current shift before changing equipment.":"Equipping consumes one spare. Replacing a worn tool discards its remaining condition."}</p><Link href="/districts/mines-and-quarries">Explore Mines & Quarries →</Link></div>
 <div className="bin-stash-note"><GameIcon name="shield" size={19}/><p>Trade your finds at the player market or keep them for later. Items listed for sale or auction are reserved until sold or withdrawn. Equipped pickaxes cannot be traded.</p></div></aside> <section className="bin-panel bin-history"><header><h2>Your recent searches</h2><span className="bin-muted">LATEST 30 / THIS SEASON</span></header>{data.history.length?<ol>{data.history.map(r=><li key={r.id}><LootArt item={r.outcome}/><div><strong>{r.outcome==="cash"?money(r.cash)+" found":loot.find(l=>l.id===r.outcome)?.name??"Nothing found"}</strong><span>{r.district_name}</span></div><time dateTime={r.created_at}>{new Date(r.created_at).toLocaleString()}</time></li>)}</ol>:<p className="bin-muted">Your first search will leave a story here.</p>}</section></div></details>
 </div>;
}
