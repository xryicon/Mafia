"use client";

import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import Link from "next/link";
import {useRouter} from "next/navigation";
import {viewPath} from "@/lib/city";
import {PropertyEstate} from "@/components/property-estate";
import { createClient } from "@/lib/supabase/client";
import { money, rank, readyUnits, remaining, duration, type GameState, type Listing } from "@/lib/game";
import { GameIcon } from "@/components/game-icon";
import { seasonPlayable } from "@/lib/seasons";
import { Artwork } from "@/components/artwork";
import {DistrictBuyOrders} from "@/components/district-buy-orders";
import { MarketPulse } from "@/components/market-pulse";

type Tab = "overview" | "operations" | "market" | "businesses" | "inventory" | "ledger";
const symbols: Record<string, string> = { whiskey: "◈", silk: "▧", steel: "▰" };
const businessCopy: Record<string, string> = {
  whiskey: "The back room keeps the city's glasses full.",
  silk: "Fine fabric. Better margins. A business with connections.",
  steel: "Every growing empire needs a steady supply of steel.",
};

function PurchaseDialog({ offer, name, fee, busy, onClose, onConfirm }: {
  offer: Listing; name: string; fee:number; busy: boolean; onClose: () => void; onConfirm: () => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => { ref.current?.showModal(); }, []);
  return <dialog ref={ref} className="deal-dialog" onCancel={event => { if (busy) event.preventDefault(); else onClose(); }} aria-labelledby="deal-title">
    <p className="eyebrow">CONFIRM THE DEAL</p><h2 id="deal-title">Buy this lot?</h2>
    <p>{offer.quantity} {name.toLowerCase()} from <strong>{offer.seller_handle}</strong>.</p>
    <dl><div><dt>Unit price</dt><dd>{money(offer.unit_price)}</dd></div><div><dt>Total from your cash</dt><dd className="gold">{money(offer.quantity * offer.unit_price)}</dd></div></dl>
    <p className="muted">The goods transfer to your inventory. The seller pays the {fee}% market fee.</p>
    <div className="deal-actions"><button className="button ghost" onClick={onClose} disabled={busy}>Back</button><button className="button" onClick={onConfirm} disabled={busy}>{busy ? "Closing deal…" : "Confirm purchase"}</button></div>
  </dialog>;
}

export function GameShell({ initial, initialTab="overview", initialGood, initialDistrict }: { initial: GameState; initialTab?:Tab; initialGood?:string; initialDistrict?:string }) {
  const [state, setState] = useState(initial);
  const jobs = state.jobs;
  const settings = state.settings;
  const [tab, setTab] = useState<Tab>(initialTab);
  const [now, setNow] = useState(Date.parse(initial.server_time));
  const [pending, setBusy] = useState(false);
  const playing = seasonPlayable(state.season, now);
  const busy = pending || !playing;
  const [refreshing, setRefreshing] = useState(false);
  const [notice, setNotice] = useState("");
  const [failed, setFailed] = useState(false);
  const [purchase, setPurchase] = useState<Listing | null>(null);
  const [filter, setFilter] = useState("all");
  const [goodId, setGoodId] = useState("whiskey");
  const [quantity, setQuantity] = useState("1");
  const [unitPrice, setUnitPrice] = useState("100");
  const [districtId,setDistrictId]=useState(initialDistrict??"");
  const [districts,setDistricts]=useState<{id:string;name:string}[]>([]);
  useEffect(()=>{void createClient().rpc("district_state").then(({data})=>{if(data)setDistricts(data.districts);});},[]);
  const busyRef = useRef(false);
  const requestNumber = useRef(0);
  const offset = useRef(0);

  const router=useRouter();
  const [propertyId,setPropertyId]=useState(initialGood||initial.businesses[0]?.good_id||initial.goods[0].id);
  useEffect(()=>{setTab(initialTab);},[initialTab]);
  useEffect(()=>{if(initialGood){setFilter(initialGood);setGoodId(initialGood);setPropertyId(initialGood);}},[initialGood]);
  const reload = useCallback(async () => {
    const version = ++requestNumber.current;
    const { data, error } = await createClient().rpc("game_state");
    if (error || !data) throw new Error("Could not refresh the city. Check your connection and try again.");
    if (version === requestNumber.current) {
      const updated = data as GameState;
      offset.current = Date.parse(updated.server_time) - Date.now();
      setNow(Date.parse(updated.server_time));
      setState(updated);
      window.dispatchEvent(new Event("blackwater:game"));
    }
  }, []);

  useEffect(() => {
    offset.current = Date.parse(initial.server_time) - Date.now();
    const timer = window.setInterval(() => setNow(Date.now() + offset.current), 1000);
    const refresh = window.setInterval(() => {
      if (!document.hidden && !busyRef.current) reload().catch(() => {
        setFailed(true); setNotice("Live refresh paused. Your last saved data is shown; use Refresh to reconnect.");
      });
    }, 30000);
    return () => { window.clearInterval(timer); window.clearInterval(refresh); };
  }, [initial.server_time, reload]);

  async function refresh() {
    if (busyRef.current || refreshing) return;
    setRefreshing(true);
    try { await reload(); setFailed(false); setNotice("City data refreshed."); }
    catch (error) { setFailed(true); setNotice(error instanceof Error ? error.message : "Refresh failed."); }
    finally { setRefreshing(false); }
  }

  async function act(action: string, payload: Record<string, string | number> = {}) {
    if (busyRef.current) return false;
    busyRef.current = true; ++requestNumber.current; setBusy(true); setNotice(""); setFailed(false);
    try {
      const { data, error } = await createClient().rpc("game_action", { p_action: action, p_payload: {...payload,season_id:state.season.id} });
      if (error || data?.error) throw new Error(data?.error || error?.message);
      setNotice(data?.message || "Done.");
      try { await reload(); }
      catch { setNotice((data?.message || "Action completed.") + " Use Refresh to see your updated totals."); }
      return true;
    } catch (error) {
      setFailed(true); setNotice(error instanceof Error ? error.message : "Could not complete this action. Refresh before trying again.");
      return false;
    } finally { busyRef.current = false; setBusy(false); }
  }

  function openTab(next: Tab, good?:string) { setTab(next); if(good){setFilter(good);setGoodId(good);}router.push(viewPath(next,good)); }
  const goodsName = (id: string) => state.goods.find(g => g.id === id)?.name || id;
  const available = (id: string) => state.inventory.find(i => i.good_id === id)?.quantity || 0;
  const cooldown = remaining(state.player.job_ready_at, now);
  const totalStock = state.inventory.reduce((sum, item) => sum + item.quantity, 0);
  const market = state.market.filter(offer => (filter === "all" || offer.good_id === filter)&&(!districtId||offer.district_id===districtId));
  const listingTotal = Number(quantity) * Number(unitPrice);
  const listingFee = Math.ceil(listingTotal * settings.market_fee_percent / 100);

  async function list(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const qty = Number(quantity), price = Number(unitPrice);
    if (!Number.isInteger(qty) || !Number.isInteger(price) || qty < 1 || qty > settings.max_listing_quantity || price < 1 || price > settings.max_unit_price) {
      setFailed(true); setNotice("Enter whole-number quantities and prices within the limits."); return;
    }
    await act("list", { good_id: goodId, quantity: qty, unit_price: price, ...(districtId?{district_id:districtId}:{}) });
  }

  function marketRows(offers: Listing[]) {
    return offers.length ? <div className="table-scroll"><table className="market-table"><thead><tr><th>Commodity / seller</th><th>Quantity</th><th>Per unit</th><th>Lot total</th><th><span className="sr-only">Trade</span></th></tr></thead><tbody>{offers.map(offer =>
      <tr key={offer.id}><td><div className="commodity"><span className={"commodity-icon " + offer.good_id}>{symbols[offer.good_id]}</span><div><strong>{goodsName(offer.good_id)}</strong><small>{offer.seller_id === state.player.id ? "YOUR OFFER" : offer.seller_handle}</small></div></div></td><td>{offer.quantity}</td><td className="gold">{money(offer.unit_price)}</td><td>{money(offer.quantity * offer.unit_price)}</td><td>{offer.seller_id === state.player.id ? <button className="table-button muted-button" disabled={busy} onClick={() => act("cancel", { listing_id: offer.id })}>Withdraw</button> : <button className="table-button" disabled={busy || state.player.cash < offer.quantity * offer.unit_price} onClick={() => setPurchase(offer)}>{state.player.cash < offer.quantity * offer.unit_price ? "Low cash" : "Buy lot"}</button>}</td></tr>
    )}</tbody></table></div> : <div className="empty-state"><GameIcon name="market" size={32}/><h3>The market is yours to make.</h3><p>No active offers{filter === "all" ? " yet" : " for this commodity"}. List goods from your inventory and set the city's first price.</p><button className="button small ghost" onClick={() => openTab("inventory")}>View your stock <GameIcon name="arrow" size={16}/></button></div>;
  }

  function businessCards() {
    return <div className="business-grid">{state.goods.map(good => {
      const owned = state.businesses.find(b => b.good_id === good.id);
      const units = owned ? readyUnits(owned, good, playing ? now : Date.parse(state.season.locked_at || state.season.ends_at || state.server_time), settings.offline_batches) : 0;
      const next = owned ? Math.max(0, good.cycle_seconds - Math.floor((now - Date.parse(owned.collected_at)) / 1000)) : 0;
      return <article className={"business-card " + good.id} key={good.id}><div className="business-art"><Artwork name={good.id==="whiskey"?"distillery":good.id==="silk"?"textile":"foundry"}/><span className={"tag " + (owned ? "green-tag" : "")}>{owned ? "OWNED" : "FOR SALE"}</span><div className="business-art-shade" /></div><div className="business-body"><p className="eyebrow">{good.id === "whiskey" ? "THE DOCKS" : good.id === "silk" ? "OLD TOWN" : "INDUSTRIAL QUARTER"}</p><h3>{good.business_name}</h3><p>{businessCopy[good.id]}</p><div className="production-line"><GameIcon name="inventory" size={15}/><span>{good.batch_size} {good.name.toLowerCase()} / {good.cycle_seconds} sec</span></div>{owned ? <><div className="business-price"><span>{units ? "READY TO COLLECT" : "NEXT BATCH"}</span><strong className={units ? "green" : ""}>{units ? units + " units" : duration(next)}</strong></div><button className="button full small" disabled={busy || units === 0} onClick={() => act("collect", { good_id: good.id })}>{units ? "Collect production" : "Production in progress"}</button></> : <><div className="business-price"><span>ACQUISITION COST</span><strong className="gold">{money(good.business_cost)}</strong></div><button className="button full small ghost" disabled={busy || state.player.cash < good.business_cost} onClick={() => act("business", { good_id: good.id })}>Buy business · {money(good.business_cost)}</button></>}<Link className="property-detail-link" href={"/properties?good="+good.id}>View property <GameIcon name="arrow" size={14}/></Link></div></article>;
    })}</div>;
  }

  const titles={overview:"Your empire.",market:"The black market.",operations:"The districts.",businesses:"Your properties.",inventory:"Your inventory.",ledger:"Follow the money."};
  const description=tab==="overview"?"A city built on ambition. An economy driven by its players. Your next move starts here.":tab==="market"?"Real players. Real offers. Supply the city, name your price, and turn your goods into a fortune.":tab==="operations"?"From the docks to the old town, opportunity is everywhere. Put your crew to work and earn your place.":tab==="inventory"?"Everything you produce and trade begins here. Your goods. Your price.":"Your private record of every dollar earned, invested and traded.";
  return <div className={"estate-game view-"+tab}>
   {tab==="businesses"?<PropertyEstate state={state} now={now} propertyId={propertyId} busy={busy} onAction={act} onSelect={id=>{setPropertyId(id);router.push(viewPath("businesses",id));}} onSell={id=>openTab("inventory",id)} notice={<>{notice && <div className={"game-notice " + (failed ? "error" : "")} role={failed ? "alert" : "status"}>{notice}<button onClick={() => setNotice("")} aria-label="Dismiss message">×</button></div>}</>}/>:<>
    <section className="estate-hero"><Artwork name={tab==="operations"?"harbor":tab==="market"||tab==="inventory"?"foundry":"exchange"} priority/><div className="estate-hero-shade"/><div className="estate-hero-copy"><p className="eyebrow">BLACKWATER <span>›</span> {tab==="overview"?"DASHBOARD":tab==="operations"?"DISTRICTS":tab.toUpperCase()}</p><h1>{titles[tab]}</h1><p className="estate-location">{state.season.name.toUpperCase()} / {state.season.status.toUpperCase()}</p><i className="estate-gold-rule"/><p className="estate-motto">Same city. Different ambitions.</p><p className="estate-description">{description}</p></div><div className="estate-hero-quote">A PLAYER-DRIVEN<br/><strong>CRIME ECONOMY.</strong></div></section>
    <div className="estate-body"><div className="estate-toolbar"><div><Link href="/market?view=inventory" aria-current={tab==="inventory"?"page":undefined}><GameIcon name="inventory" size={15}/>Inventory</Link><Link href="/ledger" aria-current={tab==="ledger"?"page":undefined}><GameIcon name="ledger" size={15}/>Ledger</Link><Link href="/seasons">{state.season.name} · {state.season.status}</Link></div><button className="refresh-button" onClick={refresh} disabled={pending||refreshing} aria-label="Refresh city data"><GameIcon name="refresh" size={15}/>{refreshing?"Refreshing…":"Refresh"}</button></div>
    <div className="stats-grid estate-stats"><article><span className="stat-icon gold"><GameIcon name="cash"/></span><div><span>CASH ON HAND</span><strong className="gold">{money(state.player.cash)}</strong><small>Available to invest & trade</small></div></article><article><span className="stat-icon violet"><GameIcon name="respect"/></span><div><span>RESPECT</span><strong>{state.player.xp.toLocaleString("en-US")} <i>RP</i></strong><small>{rank(state.player.xp, settings)}</small></div></article><article><span className="stat-icon blue"><GameIcon name="inventory"/></span><div><span>WAREHOUSE STOCK</span><strong>{totalStock.toLocaleString("en-US")} <i>units</i></strong><small>{state.my_listings.reduce((sum,l) => sum + l.quantity, 0)} reserved on the market</small></div></article><article><span className="stat-icon green"><GameIcon name="businesses"/></span><div><span>BUSINESSES</span><strong>{state.businesses.length} <i>/ {state.goods.length}</i></strong><small>{state.businesses.length ? "Your production network" : "Your first acquisition awaits"}</small></div></article></div>
    {!playing&&<p className="game-notice">This season is paused. Visit Seasons for the current standings.</p>}
    <>{notice && <div className={"game-notice " + (failed ? "error" : "")} role={failed ? "alert" : "status"}>{notice}<button onClick={() => setNotice("")} aria-label="Dismiss message">×</button></div>}</>
            {tab === "overview" && <>
          
          <MarketPulse state={state} onChoose={id=>openTab("market",id)}/><div className="overview-columns"><section className="game-panel"><div className="panel-heading"><div><p className="eyebrow">PLAYER-DRIVEN ECONOMY</p><h2>Latest market offers</h2></div><button className="link-button" onClick={() => openTab("market")}>View market <GameIcon name="arrow" size={15}/></button></div>{marketRows(state.market.slice(0,4))}<div className="panel-foot"><GameIcon name="shield" size={14}/> Goods held until sale. {settings.market_fee_percent}% seller fee. No artificial buyers.</div></section>
          <section className="game-panel next-move"><p className="eyebrow">YOUR NEXT MOVE</p><h2>Keep the cash flowing.</h2><p>Every operation earns cash and respect. Your crew needs a little time between jobs.</p><div className="operation-mini"><GameIcon name="operations" size={27}/><div><strong>Dock errand</strong><small>THE DOCKS · {jobs.find(j=>j.id==='docks')?.cooldown} SEC COOLDOWN</small></div></div><div className="reward-row"><strong className="gold">+{money(jobs.find(j=>j.id==='docks')?.reward || 0)}</strong><span className="violet">+{jobs.find(j=>j.id==='docks')?.xp} RP</span></div><button className="button full" disabled={busy || cooldown > 0} onClick={() => act("job", { job: "docks" })}>{cooldown > 0 ? "Crew ready in " + duration(cooldown) : "Complete dock errand"}</button><button className="link-button centered" onClick={() => openTab("operations")}>All operations <GameIcon name="arrow" size={15}/></button></section></div>
          <section className="business-section"><div className="section-heading"><div><p className="eyebrow">BUILD YOUR FOUNDATION</p><h2>Business opportunities</h2></div><button className="link-button" onClick={() => openTab("businesses")}>Manage businesses <GameIcon name="arrow" size={15}/></button></div>{businessCards()}</section>
        </>}
        {tab === "operations" && <><div className="cooldown-banner"><GameIcon name="clock"/><strong>{cooldown ? "Crew cooldown · " + duration(cooldown) : "Your crew is ready for an operation."}</strong><span>Rewards are paid on completion; cooldown begins immediately.</span></div><div className="operations-grid">{jobs.map((job,i) => <article className="operation-card" key={job.id}><div className={"operation-art scene-" + i}><Artwork name={i===0?"harbor":i===1?"textile":"exchange"}/><div className="operation-shade"/><span>0{i+1}</span><GameIcon name="operations" size={60}/></div><div className="operation-body"><p className="eyebrow">{job.district}</p><h2>{job.name}</h2><p>{job.description}</p><div className="operation-time"><GameIcon name="clock" size={14}/>{duration(job.cooldown)} crew cooldown</div><div className="reward-row"><strong className="gold">+{money(job.reward)}</strong><span className="violet">+{job.xp} RP</span></div><button className="button full" disabled={busy || cooldown > 0} onClick={() => act("job", { job: job.id })}>{cooldown ? "Ready in " + duration(cooldown) : "Complete operation"}</button></div></article>)}</div></>}

        {tab === "market" && <><MarketPulse state={state} onChoose={id=>setFilter(id)}/><section className="game-panel"><div className="panel-heading"><div><p className="eyebrow">LATEST 200 OPEN OFFERS</p><h2>Trading floor</h2></div><button className="button small" onClick={() => openTab("inventory")}>Create an offer <GameIcon name="arrow" size={15}/></button></div><label className="market-district-selector">District market<select value={districtId} onChange={e=>setDistrictId(e.target.value)}><option value="">All districts</option>{districts.map(d=><option key={d.id} value={d.id}>{d.name}</option>)}</select></label><div className="market-filters" aria-label="Filter commodities">{[{id:"all",name:"All goods"},...state.goods].map(g => <button key={g.id} className={filter === g.id ? "selected" : ""} aria-pressed={filter === g.id} onClick={() => setFilter(g.id)}>{g.name}</button>)}</div>{marketRows(market)}<div className="panel-foot">Whole lots only · {settings.market_fee_percent}% seller fee, rounded up to the next dollar · Updates every 30 seconds</div></section><DistrictBuyOrders districtId={districtId} game={state} onChange={reload}/><section className="game-panel own-offers"><div className="panel-heading"><h2>Your active offers</h2><span className="muted">{state.my_listings.length} / {settings.listing_limit}</span></div>{state.my_listings.length ? marketRows(state.my_listings) : <p className="panel-empty">You haven't listed any goods. Start from your inventory.</p>}</section></>}
        {tab === "inventory" && <div className="inventory-layout"><section className="game-panel"><div className="panel-heading"><h2>Available stock</h2><span className="muted">Ready to trade</span></div>{state.goods.map(g => <div className="inventory-row" key={g.id}><span className={"commodity-icon large " + g.id}>{symbols[g.id]}</span><div><strong>{g.name}</strong><small>{state.my_listings.filter(l => l.good_id === g.id).reduce((sum,l) => sum+l.quantity,0)} reserved in offers</small></div><strong className="inventory-count">{available(g.id)} <small>units</small></strong><button className="table-button" disabled={!available(g.id)} onClick={() => {setGoodId(g.id);setQuantity("1");document.getElementById("offer-good")?.focus();}}>Sell</button></div>)}<div className="panel-foot">Listed goods leave available stock. Withdraw an offer to return them.</div></section><section className="game-panel sell-panel"><p className="eyebrow">YOUR GOODS. YOUR PRICE.</p><h2>Create an offer</h2><form onSubmit={list}><label>Trading district<select value={districtId} onChange={e=>setDistrictId(e.target.value)}><option value="">City exchange</option>{districts.map(d=><option key={d.id} value={d.id}>{d.name}</option>)}</select></label><label htmlFor="offer-good">Commodity<select id="offer-good" value={goodId} onChange={e => {setGoodId(e.target.value);setQuantity("1");}}>{state.goods.map(g => <option key={g.id} value={g.id}>{g.name} · {available(g.id)} available</option>)}</select></label><div className="form-grid"><label htmlFor="offer-quantity">Quantity<input id="offer-quantity" type="number" min="1" max={Math.max(1,Math.min(settings.max_listing_quantity,available(goodId)))} step="1" required value={quantity} onChange={e => setQuantity(e.target.value)}/></label><label htmlFor="offer-price">Price per unit ($)<input id="offer-price" type="number" min="1" max={settings.max_unit_price} step="1" required value={unitPrice} onChange={e => setUnitPrice(e.target.value)}/></label></div><div className="offer-summary"><div><span>Lot price</span><strong>{money(listingTotal || 0)}</strong></div><div><span>Seller fee ({settings.market_fee_percent}%, rounded up)</span><span>{money(Number.isFinite(listingFee) ? listingFee : 0)}</span></div><div><span>You receive if sold</span><strong className="gold">{money(Math.max(0, listingTotal - listingFee) || 0)}</strong></div></div><button className="button full" disabled={busy || !available(goodId) || state.my_listings.length >= settings.listing_limit}>{busy ? "Please wait…" : "Post market offer"}</button><p className="form-help">Up to {settings.max_listing_quantity.toLocaleString()} units per offer. No listing charge. Your stock is reserved until sold or withdrawn.</p></form></section></div>}
        {tab === "ledger" && <section className="game-panel"><div className="panel-heading"><h2>Your latest financial entries</h2><span className="tag">PRIVATE LEDGER</span></div>{state.ledger.map(event => <div className="ledger-row" key={event.id}><span className={"ledger-icon " + (event.delta >= 0 ? "green" : "red")}><GameIcon name={event.delta ? "cash" : "inventory"}/></span><div><strong>{event.reason} · Balance {money(event.balance_after)}</strong><small>{new Intl.DateTimeFormat("en-GB",{dateStyle:"medium",timeStyle:"short",timeZone:"UTC"}).format(new Date(event.created_at))} UTC</small></div><span className={event.delta > 0 ? "green" : event.delta < 0 ? "red" : "muted"}>{event.delta ? (event.delta > 0 ? "+" : "−") + money(Math.abs(event.delta)) : "—"}</span></div>)}</section>}

    </div>
   </>}
   {purchase&&<PurchaseDialog offer={purchase} name={goodsName(purchase.good_id)} fee={settings.market_fee_percent} busy={busy} onClose={()=>setPurchase(null)} onConfirm={async()=>{await act("buy",{listing_id:purchase.id});setPurchase(null);}}/>}
  </div>;
}
