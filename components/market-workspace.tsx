"use client";
import {useCallback,useEffect,useRef,useState,type FormEvent,type ReactNode} from "react";
import Link from "next/link";
import {useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase/client";
import {GameIcon} from "@/components/game-icon";
import {DistrictBuyOrders} from "@/components/district-buy-orders";
import {money,type Listing} from "@/lib/game";
import {seasonPlayable} from "@/lib/seasons";
import {auctionTime,goodIcon,nextBid,type Auction,type MarketState,type MarketView} from "@/lib/market";

type Action=(action:string,payload:Record<string,unknown>,auction?:boolean)=>Promise<boolean>;
type Request={action:string;payload:Record<string,unknown>;auction:boolean};
function Panel({title,children,className=""}:{title:string;children:ReactNode;className?:string}){
 return <section className={"command-panel "+className}><div className="command-panel-head"><h2>{title}</h2></div>{children}</section>;
}
function Deal({offer,auction,game,busy,onClose,onBuy,onBid}:{offer:Listing|null;auction:Auction|null;game:MarketState["game"];busy:boolean;onClose:()=>void;onBuy:()=>void;onBid:(amount:number)=>void}){
 const dialog=useRef<HTMLDialogElement>(null),[amount,setAmount]=useState(String(auction?nextBid(auction):0));
 useEffect(()=>{dialog.current?.showModal();},[]);
 const name=game.goods.find(g=>g.id===(auction?.good_id??offer?.good_id))?.name??"Goods";
 const total=auction?Number(amount):(offer?.quantity??0)*(offer?.unit_price??0);
 return <dialog ref={dialog} className="command-modal market-deal" aria-labelledby="market-deal-title" onCancel={e=>{if(busy)e.preventDefault();else onClose();}}>
  <button className="market-close" onClick={onClose} disabled={busy} aria-label="Close deal">×</button>
  <p className="eyebrow">{auction?"THE AUCTION ROOM":"CONFIRM THE DEAL"}</p><h2 id="market-deal-title">{auction?"Place your bid.":"Buy this lot?"}</h2>
  <p>{auction?.quantity??offer?.quantity} {name} · {auction?.seller_name??offer?.seller_handle}</p>
  <form onSubmit={e=>{e.preventDefault();if(auction)onBid(Number(amount));else onBuy();}}>
   {auction&&<><label>Your bid for the whole lot<input type="number" required min={nextBid(auction)} max={game.settings.auction_max_bid} step="1" value={amount} onChange={e=>setAmount(e.target.value)}/></label><p className="market-help">Next bid: {money(nextBid(auction))}. Minimum increase: {money(auction.increment)}.</p></>}
   <dl className="market-receipt"><div><dt>{auction?"Bid total":"Lot total"}</dt><dd>{money(total)}</dd></div><div><dt>{auction?"Additional cash reserved":"Paid from cash"}</dt><dd>{money(total-(auction?.bidder_id===game.player.id?auction.escrow:0))}</dd></div></dl>
   <p className="market-help">{auction?"Your bid is held until you win or are outbid. Outbid cash returns automatically. Bids cannot be withdrawn.":"The whole lot transfers to your inventory. The seller pays the market fee."}</p>
   {auction&&auction.extension_seconds>0&&<p className="market-help">A late bid leaves at least {auction.extension_seconds} seconds to respond, up to the season deadline.</p>}
   <button className="market-gold" disabled={busy||total>game.player.cash+(auction?.bidder_id===game.player.id?auction.escrow:0)}>{busy?"Confirming…":auction?"Confirm bid":"Confirm purchase"}<GameIcon name="arrow" size={16}/></button>
  </form>
 </dialog>;
}
function SellTicket({data,good,district,busy,onSelect,onAction}:{data:MarketState;good:string;district:string;busy:boolean;onSelect:(id:string)=>void;onAction:Action}){
 const [mode,setMode]=useState<"fixed"|"auction">("fixed"),[quantity,setQuantity]=useState("1"),[price,setPrice]=useState("100");
 const settings=data.game.settings;
 const [minutes,setMinutes]=useState(String(Math.max(settings.auction_min_minutes,Math.min(settings.auction_max_minutes,settings.auction_default_minutes))));
 const stock=data.game.inventory.find(i=>i.good_id===good)?.quantity??0;
 const total=mode==="auction"?Number(price):Number(price)*Number(quantity),fee=Math.ceil(total*settings.market_fee_percent/100);
 async function submit(e:FormEvent){e.preventDefault();await onAction(mode==="auction"?"create":"list",{good_id:good,quantity:Number(quantity),...(district?{district_id:district}:{}),...(mode==="auction"?{starting_bid:Number(price),duration_minutes:Number(minutes)}:{unit_price:Number(price)})},mode==="auction");}
 return <Panel title="Create a listing" className="market-ticket">
  <p className="market-help">Your goods. Your terms.</p>
  <div className="market-sale-choice" role="group" aria-label="Sale format"><button aria-pressed={mode==="fixed"} onClick={()=>setMode("fixed")}><GameIcon name="trade" size={17}/>Fixed price</button><button aria-pressed={mode==="auction"} onClick={()=>setMode("auction")}><GameIcon name="auction" size={17}/>Auction</button></div>
  <form onSubmit={submit}>
   <label>Commodity<select value={good} onChange={e=>onSelect(e.target.value)}>{data.game.goods.map(g=><option key={g.id} value={g.id}>{g.name}</option>)}</select></label>
   <div className="market-stock-note"><GameIcon name="inventory" size={14}/>{stock.toLocaleString("en-US")} units available</div>
   <label>Quantity<input type="number" min="1" max={Math.min(stock,settings.max_listing_quantity)} step="1" required value={quantity} onChange={e=>setQuantity(e.target.value)}/></label>
   <label>{mode==="fixed"?"Price per unit ($)":"Starting bid for whole lot ($)"}<input type="number" min="1" max={mode==="fixed"?settings.max_unit_price:settings.auction_max_bid} step="1" required value={price} onChange={e=>setPrice(e.target.value)}/></label>
   {mode==="auction"&&<label>Duration (minutes)<input aria-label="Duration (minutes)" type="number" min={settings.auction_min_minutes} max={settings.auction_max_minutes} step="1" required value={minutes} onChange={e=>setMinutes(e.target.value)}/><small>{settings.auction_min_minutes}–{settings.auction_max_minutes} minutes allowed</small></label>}
   <dl className="market-receipt"><div><dt>{mode==="fixed"?"Lot value":"Opening lot value"}</dt><dd>{money(total)}</dd></div><div><dt>Seller fee · {settings.market_fee_percent}%</dt><dd>{money(fee)}</dd></div><div className="market-net"><dt>{mode==="fixed"?"You receive":"At the opening bid"}</dt><dd>{money(Math.max(0,total-fee))}</dd></div></dl>
   <p className="market-help">{mode==="auction"?"Goods are reserved until the auction ends. The highest funded bid wins. Withdraw only before the first bid.":"Goods are reserved until sold or withdrawn. Buyers purchase the whole lot."}</p>
   <p className="market-location"><GameIcon name="district" size={14}/>{data.districts.find(d=>d.id===district)?.name??"City exchange"}</p>
   <button className="market-gold" disabled={busy||stock<1}>{mode==="auction"?"Start auction":"Post market offer"}<GameIcon name="arrow" size={16}/></button>
  </form>
 </Panel>;
}

export function MarketWorkspace({initial,initialView,initialGood,initialDistrict}:{initial:MarketState;initialView:MarketView;initialGood?:string;initialDistrict?:string}){
 const [data,setData]=useState(initial),[view,setView]=useState(initialView),[filter,setFilter]=useState(initialGood??"all"),[district,setDistrict]=useState(initialDistrict??"");
 const [good,setGood]=useState(initial.game.goods.some(g=>g.id===initialGood)?initialGood!:initial.game.goods[0]?.id??"");
 const [search,setSearch]=useState(""),[sort,setSort]=useState("latest"),[notice,setNotice]=useState(""),[failed,setFailed]=useState(false),[busy,setBusy]=useState(false),[retry,setRetry]=useState<Request|null>(null);
 const [purchase,setPurchase]=useState<Listing|null>(null),[bid,setBid]=useState<Auction|null>(null),[now,setNow]=useState(Date.parse(initial.server_time));
 const inFlight=useRef(false),sequence=useRef(0),offset=useRef(Date.parse(initial.server_time)-Date.now()),router=useRouter();
 const game=data.game,settings=game.settings,playing=seasonPlayable(game.season,now),disabled=busy||!!retry||!playing;
 useEffect(()=>{setView(initialView);},[initialView]);
 useEffect(()=>{setFilter(initialGood??"all");if(initialGood)setGood(initialGood);setDistrict(initialDistrict??"");},[initialGood,initialDistrict]);
 const reload=useCallback(async()=>{
  const version=++sequence.current;const r=await createClient().rpc("market_state");
  if(r.error||!r.data)throw new Error("The exchange could not refresh. Try again.");
  if(version===sequence.current){setData(r.data);offset.current=Date.parse(r.data.server_time)-Date.now();setNow(Date.now()+offset.current);window.dispatchEvent(new Event("blackwater:game"));}
 },[]);
 useEffect(()=>{
  const clock=setInterval(()=>setNow(Date.now()+offset.current),1000);
  const refresh=()=>{if(!document.hidden&&!inFlight.current)void reload().catch(()=>{setFailed(true);setNotice("Live updates paused. Refresh to reconnect.");});};
  const poll=setInterval(refresh,15000);window.addEventListener("focus",refresh);document.addEventListener("visibilitychange",refresh);
  return()=>{clearInterval(clock);clearInterval(poll);window.removeEventListener("focus",refresh);document.removeEventListener("visibilitychange",refresh);sequence.current++;};
 },[reload]);
 async function act(action:string,payload:Record<string,unknown>,auction=false){
  if(inFlight.current)return false;
  inFlight.current=true;++sequence.current;setBusy(true);setNotice("");setFailed(false);
  const request:Request={action,auction,payload:{...payload,season_id:game.season.id,...(auction?{request_id:payload.request_id??crypto.randomUUID()}:{})}};
  let uncertain=auction;
  try{
   const r=await createClient().rpc(auction?"market_auction_action":"game_action",{p_action:action,p_payload:request.payload});
   if(r.error)throw new Error("The response was interrupted. "+(auction?"Retry this request to safely confirm the result.":"Refresh and check your listings before trying again."));
   uncertain=false;setRetry(null);
   if(r.data?.error)throw new Error(r.data.error);
   setNotice(r.data?.message??"Deal complete.");
   try{await reload();}catch{setNotice((r.data?.message??"Deal complete.")+" Refresh to see your updated totals.");}
   return true;
  }catch(e){setFailed(true);setNotice(e instanceof Error?e.message:"Could not complete the deal.");if(uncertain)setRetry(request);return false;}
  finally{inFlight.current=false;setBusy(false);}
 }
 function go(next:MarketView){
  setView(next);const query=new URLSearchParams();if(next!=="floor")query.set("view",next);if(filter!=="all")query.set("good",filter);if(district)query.set("district",district);router.push("/market"+(query.size?"?"+query:""),{scroll:false});
 }
 const name=(id:string)=>game.goods.find(g=>g.id===id)?.name??id;
 const matches=(id:string,seller:string,d:string|null|undefined)=>(filter==="all"||filter===id)&&(!district||district===d)&&(!search||(name(id)+" "+seller).toLowerCase().includes(search.toLowerCase()));
 const fixed=(view==="mine"?game.my_listings:game.market).filter(l=>matches(l.good_id,l.seller_handle,l.district_id)).sort((a,b)=>sort==="price"?a.unit_price-b.unit_price:Date.parse(b.created_at)-Date.parse(a.created_at));
 const auctions=data.auctions.filter(a=>matches(a.good_id,a.seller_name,a.district_id)&&(view==="mine"?(a.seller_id===game.player.id||a.has_bid):a.status==="open")).sort((a,b)=>sort==="price"?(a.current_bid||a.starting_bid)/a.quantity-(b.current_bid||b.starting_bid)/b.quantity:Date.parse(a.ends_at)-Date.parse(b.ends_at));
 const stock=game.inventory.reduce((n,i)=>n+i.quantity,0),openAuctions=data.auctions.filter(a=>a.status==="open");
 function offers(){return fixed.length?<div className={"market-book "+(view==="mine"?"own-offers":"")}>{fixed.map(l=><article className="market-lot" key={l.id}>
  <div className="market-commodity"><span className="market-item-icon"><GameIcon name={goodIcon(l.good_id)} size={28}/></span><div><strong>{name(l.good_id)}</strong><Link href={"/players/"+l.seller_id}>{l.seller_id===game.player.id?"Your listing":l.seller_handle}</Link></div></div>
  <div><small>QUANTITY</small><strong>{l.quantity.toLocaleString("en-US")} <i>units</i></strong></div><div><small>PER UNIT</small><strong>{money(l.unit_price)}</strong></div><div><small>LOT TOTAL</small><strong className="market-gold-text">{money(l.quantity*l.unit_price)}</strong></div>
  {l.seller_id===game.player.id?<button className="market-outline" disabled={disabled} onClick={()=>act("cancel",{listing_id:l.id})}>Withdraw</button>:<button className="market-outline" disabled={disabled||game.player.cash<l.quantity*l.unit_price} onClick={()=>setPurchase(l)}>{game.player.cash<l.quantity*l.unit_price?"Low cash":"Buy lot"}<GameIcon name="arrow" size={15}/></button>}
 </article>)}</div>:<div className={"market-empty "+(view==="mine"?"own-offers":"")}><GameIcon name="trade" size={32}/><h3>{view==="mine"?"You haven't listed any goods":"No offers in this exchange."}</h3><p>Choose a commodity and set your terms using Create a listing.</p></div>;}
 function auctionRows(){return auctions.length?<div className="market-auction-grid">{auctions.map(a=>{
  const yours=a.seller_id===game.player.id,leading=a.bidder_id===game.player.id,ended=a.status!=="open"||now>=Date.parse(a.ends_at);
  return <article className={"market-auction "+(leading?"leading":"")} key={a.id} data-auction={a.id}><div className="market-auction-top"><span className="market-tag">{a.status==="open"?(leading?"YOU'RE LEADING":yours?"YOUR AUCTION":"LIVE AUCTION"):a.status.toUpperCase()}</span><time dateTime={a.ends_at}>{a.status==="open"?auctionTime(a.ends_at,now):new Date(a.completed_at??a.ends_at).toLocaleDateString("en-GB")}</time></div>
   <div className="market-commodity"><span className="market-item-icon"><GameIcon name={goodIcon(a.good_id)} size={32}/></span><div><strong>{name(a.good_id)}</strong><small>{a.quantity.toLocaleString("en-US")} units · <Link href={"/players/"+a.seller_id}>{a.seller_name}</Link></small></div></div>
   <div className="market-bid-price"><div><small>{a.bid_count?"HIGHEST BID":"STARTING BID"} · WHOLE LOT</small><strong>{money(a.current_bid||a.starting_bid)}</strong></div><span>{a.bid_count} bid{a.bid_count===1?"":"s"}</span></div>
   <p className="market-help">{a.bidder_name?"Leading bidder: "+a.bidder_name:"Be the first to make a move."}{a.status==="open"&&a.bid_count>0&&!yours&&!leading&&a.has_bid?" You've been outbid; your cash was refunded.":""}</p>
   {a.status==="open"?(ended?<button className="market-outline" disabled={disabled} onClick={()=>act("settle",{auction_id:a.id},true)}>Settle auction</button>:yours?<button className="market-outline" disabled={disabled||a.bid_count>0} onClick={()=>act("cancel",{auction_id:a.id},true)}>{a.bid_count?"Bidding in progress":"Withdraw auction"}</button>:<button className="market-outline" disabled={disabled||nextBid(a)>game.player.cash+(leading?a.escrow:0)||nextBid(a)>settings.auction_max_bid} onClick={()=>setBid(a)}>{leading?"Raise bid":"Place bid"}<span>{money(nextBid(a))}</span></button>):<p className="market-result">{a.status==="sold"?(leading?"Won · goods delivered":yours?"Sold · "+money(a.current_bid-a.fee_paid)+" received":"Auction complete"):"Goods returned to seller"}</p>}
  </article>;
 })}</div>:<div className="market-empty"><GameIcon name="auction" size={32}/><h3>No auctions here yet.</h3><p>Choose Auction in Create a listing to put your goods under the hammer.</p></div>;}


 return <div className="market-workspace">
  <header className="command-panel market-masthead"><div><p className="eyebrow">BLACKWATER / PLAYER MARKET</p><h1>The Exchange</h1><p>Fortunes change hands here.</p><span>{game.season.name} · {game.season.status}</span></div><div className="market-masthead-right"><span className="market-live"><i/>A PLAYER-DRIVEN ECONOMY</span><p>Buy the supply.<br/>Name the price. Make your move.</p><button className="command-more" disabled={busy} onClick={()=>void reload().catch(e=>{setFailed(true);setNotice(e.message);})}><GameIcon name="refresh" size={15}/>Refresh market</button><button className="market-outline market-create-shortcut" onClick={()=>{document.querySelector(".market-ticket")?.scrollIntoView({behavior:"smooth",block:"start"});(document.querySelector(".market-ticket select") as HTMLSelectElement|null)?.focus({preventScroll:true});}}>Create a listing <GameIcon name="arrow" size={14}/></button></div></header>
  <div className="market-wallet-stats">{[["cash","AVAILABLE CASH",money(game.player.cash),"Ready for your next deal"],["inventory","YOUR STOCK",stock.toLocaleString("en-US")+" units",data.reserved_stock+" units held in auctions"],["auction","BID RESERVES",money(data.reserved_cash),"Refunded when you're outbid"],["trade","YOUR OPEN LISTINGS",String(game.my_listings.length+openAuctions.filter(a=>a.seller_id===game.player.id).length),"Fixed price & auctions"]].map(([icon,title,value,note])=><article className="command-panel" key={title}><GameIcon name={icon} size={23}/><div><small>{title}</small><strong>{value}</strong><span>{note}</span></div></article>)}</div>
  {(notice||!playing)&&<div className={"market-notice game-notice "+(failed?"error":"")} role={failed?"alert":"status"}>{notice||"This season is paused. Existing listings and bids are preserved."}{retry&&<button className="market-outline" disabled={busy} onClick={()=>void act(retry.action,retry.payload,retry.auction)}>Retry same request</button>}</div>}
  <div className="market-columns">
   <aside className="market-left"><Panel title="The trading desk"><nav className="market-sections" aria-label="Market sections">{([["floor","Trading floor","trade"],["auctions","Auctions","auction"],["mine","My listings","ledger"],["inventory","Inventory","inventory"],["orders","Buy orders","cash"]] as const).map(([id,label,icon])=><button key={id} aria-current={view===id?"page":undefined} onClick={()=>go(id)}><GameIcon name={icon} size={18}/>{label}<GameIcon name="arrow" size={14}/></button>)}</nav></Panel>
    <Panel title="Commodities" className="market-commodities"><button className={filter==="all"?"selected":""} onClick={()=>setFilter("all")}>All commodities<span>{game.goods.length}</span></button>{game.goods.map(g=><button key={g.id} className={filter===g.id?"selected":""} onClick={()=>{setFilter(g.id);setGood(g.id);}}><GameIcon name={goodIcon(g.id)} size={18}/>{g.name}<span>{game.inventory.find(i=>i.good_id===g.id)?.quantity??0}</span></button>)}</Panel>
    <Panel title="House rules" className="market-rules"><GameIcon name="shield" size={26}/><p>Every offer comes from a player. Every deal moves the city.</p><ul><li>{settings.market_fee_percent}% seller fee on fixed-price sales.</li><li>Auction fees are fixed when listed.</li><li>Bid on the whole lot, with cash in reserve.</li><li>Expired auctions settle automatically.</li></ul><Link href="/ledger">View financial history <GameIcon name="arrow" size={14}/></Link></Panel>
   </aside>
   <section className="market-main" aria-label="Exchange listings">
    <div className="command-panel market-search"><label><span className="sr-only">Search goods or seller</span><GameIcon name="search" size={16}/><input placeholder="Search commodities or a player…" value={search} onChange={e=>setSearch(e.target.value)}/></label><label><span className="sr-only">District market</span><select value={district} onChange={e=>setDistrict(e.target.value)}><option value="">All districts</option>{data.districts.map(d=><option key={d.id} value={d.id}>{d.name}</option>)}</select></label><label><span className="sr-only">Sort listings</span><select value={sort} onChange={e=>setSort(e.target.value)}><option value="latest">Latest / ending soon</option><option value="price">Lowest unit price</option></select></label></div>
    {(view==="floor"||view==="mine")&&<Panel title={view==="mine"?"Your fixed-price listings":"Fixed-price offers"} className="market-floor"><p className="market-section-note">{fixed.length} offer{fixed.length===1?"":"s"} · whole lots · prices set by players</p>{offers()}</Panel>}
    {(view==="auctions"||view==="mine"||view==="floor")&&<Panel title={view==="mine"?"Your auctions & bids":"The auction room"}><div className="market-auction-heading"><p>Goods with a deadline. Influence with a price.</p><span className="market-tag">{auctions.filter(a=>a.status==="open").length} OPEN</span></div>{auctionRows()}</Panel>}
    {view==="inventory"&&<Panel title="Your warehouse"><p className="market-section-note">Available stock · choose goods to create a listing</p><div className="market-inventory">{game.goods.filter(g=>filter==="all"||filter===g.id).map(g=><button key={g.id} className={good===g.id?"selected":""} onClick={()=>setGood(g.id)}><GameIcon name={goodIcon(g.id)} size={30}/><strong>{g.name}</strong><span>{game.inventory.find(i=>i.good_id===g.id)?.quantity??0} units</span><small>Select to sell or auction <GameIcon name="arrow" size={13}/></small></button>)}</div></Panel>}
    {view==="orders"&&<DistrictBuyOrders districtId={district} game={game} onChange={reload}/>}
    <Panel title="Your recent market activity" className="market-history">{game.events.filter(e=>/bought|sold|auction|listed|offer|outbid|market/i.test(e.description)).slice(0,6).map(e=><div key={e.id}><GameIcon name="ledger" size={16}/><span>{e.description}</span><time>{new Date(e.created_at).toLocaleTimeString("en-GB",{hour:"2-digit",minute:"2-digit"})}</time>{e.cash_delta!==0&&<strong className={e.cash_delta>0?"command-green":"command-red"}>{e.cash_delta>0?"+":""}{money(e.cash_delta)}</strong>}</div>)}{!game.events.some(e=>/bought|sold|auction|listed|offer|outbid|market/i.test(e.description))&&<p className="market-help">Your trades will appear here. Your full cash history is always in the ledger.</p>}<Link className="command-more" href="/ledger">Open your ledger <GameIcon name="arrow" size={14}/></Link></Panel>
   </section>
   <aside className="market-right"><SellTicket data={data} good={good} district={district} busy={disabled} onSelect={setGood} onAction={act}/><Panel title="From your warehouses" className="market-supply"><img src="/art/exchange.webp" alt="Blackwater's trading district at night" width={420} height={180}/><p>Supply the city.<br/><em>Build your advantage.</em></p><Link className="market-outline" href="/dashboard">Manage production <GameIcon name="arrow" size={16}/></Link></Panel></aside>
  </div>
  {(purchase||bid)&&<Deal key={purchase?.id??bid?.id} offer={purchase} auction={bid} game={game} busy={disabled} onClose={()=>{setPurchase(null);setBid(null);}} onBuy={()=>void act("buy",{listing_id:purchase!.id}).then(()=>setPurchase(null))} onBid={amount=>void act("bid",{auction_id:bid!.id,amount},true).then(()=>setBid(null))}/>}
 </div>;
}

