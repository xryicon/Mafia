"use client";
import Link from "next/link";
import {useEffect,useState} from "react";
import {PropertyStock} from "./property-stock";
import {GameIcon} from "@/components/game-icon";
import {money} from "@/lib/game";
import type {DistrictState,Plot} from "@/lib/districts";
import type {DistrictAction} from "./district-details";

const buildingArt:Record<string,string>={warehouse:"/art/harbor-small.webp",garage:"/art/exchange-small.webp",foundry:"/art/foundry-small.webp",workshop:"/art/textile-small.webp",distillery:"/art/distillery-small.webp",telegram:"/art/telegram-office.jpg",refinery:"/art/foundry-small.webp"};
function cityLeaseAvailable(p:Plot,state:DistrictState){return p.owner_type==="city"&&p.status==="owned"&&p.asking_price===null&&!state.auctions.some(a=>a.plot_id===p.id)&&state.district.status!=="lockdown"&&state.territory.status!=="lockdown"&&state.property_storage?.some(s=>s.plot_id===p.id&&s.enabled)&&state.buildings.some(b=>b.plot_id===p.id&&b.construction_status==="ready"&&b.condition>0);}
export function propertyImage(p:Plot,state:DistrictState){
 return p.image_url||buildingArt[state.buildings.find(b=>b.plot_id===p.id)?.building_type??""]||state.district.image_url;
}
export function DistrictPropertyHeader({state}:{state:DistrictState}){
 const d=state.district,telegram=state.businesses.find(b=>b.telegram_fee!==null);
 return <div className="dp-masthead"><header className="dp-banner" style={{backgroundImage:'linear-gradient(90deg,#071114ef,#07111440),url("'+d.image_url+'")'}}>
 <Link className="dp-back" href="/districts">City map <span>› {d.name}</span></Link>
 <p className="dp-eyebrow">BLACKWATER / {d.district_type} DISTRICT</p><h1>{d.name}</h1>
 <p className="dp-tagline">{d.tagline}</p><span className="dp-rule"/><p className="dp-description">{d.description}</p>
 <div className="dp-banner-foot"><span>{state.season.name}</span><Link href={"/bin-diving?district="+d.slug}>Scavenging ↗</Link></div>
 </header><aside className="dp-summary"><h2>District overview</h2><dl>
 {[[ "Controller",state.territory.controller_name||"Neutral"],["Police heat",d.police_heat+" / 100"],
 ["Average land value",money(state.plots.length?state.plots.reduce((n,p)=>n+p.base_price,0)/state.plots.length:0)],
 ["Main industry",d.industries[0]||"Mixed industry"],["District tax",d.tax_rate+"%"],["Status",state.territory.status||d.status]].map(([label,value])=><div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}
 </dl><Link href="/telegrams" className="dp-summary-link"><GameIcon name="mail" size={18}/>{telegram?"Telegram Office · "+money(telegram.telegram_fee!):"City Telegram Office"}<span>→</span></Link>
 {state.can_manage&&<Link className="dp-summary-link" href={"/districts/manage?district="+d.slug}>Owner property controls →</Link>}</aside></div>;
}
export function DistrictProperties({state,onSelect,onSection}:{state:DistrictState;onSelect:(id:string)=>void;onSection:(tab:"Plots"|"Businesses"|"Territory"|"Activity")=>void}){
 const [street,setStreet]=useState(""),[filter,setFilter]=useState("all"),[query,setQuery]=useState("");
 const isMine=(p:Plot)=>p.owner_id===state.player_id||state.leases?.some(l=>l.plot_id===p.id&&l.player_id===state.player_id&&l.active)||state.property_storage?.some(s=>s.plot_id===p.id&&s.can_access);
 const holdings=state.plots.filter(isMine).length;
 useEffect(()=>{const sync=()=>{const mine=new URLSearchParams(window.location.search).get("view")==="mine";setFilter(mine?"mine":"all");setStreet(mine?"all":"");};sync();window.addEventListener("popstate",sync);return()=>window.removeEventListener("popstate",sync);},[state.district.id]);
 const chooseFilter=(value:string)=>{setFilter(value);if(value==="mine")setStreet("all");const url=new URL(window.location.href);if(value==="mine")url.searchParams.set("view","mine");else url.searchParams.delete("view");window.history.pushState(null,"",url);};
 const streets=(state.streets??[]).filter(s=>!s.archived_at),active=streets.find(s=>s.id===street)??streets[0],others=state.plots.some(p=>!streets.some(s=>s.id===p.street_id));
 const current=street==="all"?null:active,visible=state.plots.filter(p=>{
  const lease=state.lease_terms?.find(t=>t.template_id===p.template_id&&t.enabled),held=state.leases?.some(l=>l.plot_id===p.id&&l.active);
  const name=state.businesses.find(b=>b.plot_id===p.id)?.name??"";
  return (!current||p.street_id===current.id)&&(p.code+" "+name+" "+p.owner_name).toLowerCase().includes(query.toLowerCase())
   &&(filter==="all"||filter==="rent"&&!!lease&&cityLeaseAvailable(p,state)||filter==="sale"&&(p.status==="available"||p.asking_price!==null)||filter==="mine"&&isMine(p)||filter==="storage"&&state.property_storage?.some(s=>s.plot_id===p.id))&&!(filter==="rent"&&held);
 });
 const counts=[...new Set(state.businesses.map(b=>b.business_type))].map(type=>[type,state.businesses.filter(b=>b.business_type===type&&b.status==="open").length] as const);
 return <div className="dp-registry">
 <nav className="dp-property-views" aria-label="Property views"><button aria-pressed={filter!=="mine"} onClick={()=>{chooseFilter("all");setStreet("");setQuery("");}}><GameIcon name="district" size={22}/><span>Explore district<small>Streets, properties and opportunities</small></span></button><button aria-pressed={filter==="mine"} onClick={()=>{chooseFilter("mine");setQuery("");}}><GameIcon name="property" size={22}/><span>Your properties &amp; leases<small>{holdings} {holdings===1?"property":"properties"} · Manage storage and workspace</small></span></button></nav>
 {filter!=="mine"&&<nav className="dp-streets" aria-label="District streets">{streets.map(s=><button key={s.id} aria-current={current?.id===s.id?"page":undefined} onClick={()=>setStreet(s.id)}><GameIcon name="districts" size={22}/><span>{s.name}<small>{state.plots.filter(p=>p.street_id===s.id).length} properties</small></span></button>)}
 {(others||streets.length>0)&&<button aria-current={street==="all"?"page":undefined} onClick={()=>setStreet("all")}>All properties</button>}<button className="dp-map-shortcut" onClick={()=>onSection("Plots")}><GameIcon name="districts" size={19}/>View district map →</button></nav>}
 <div className="dp-body"><section className="dp-properties"><header className="dp-heading"><div><h2>{filter==="mine"?"Your properties & leases":current?.name||"District properties"}</h2><p>{filter==="mine"?"All your owned properties, active leases and collection lockers in this district.":current?.description||"Find your place in the Blackwater economy."}</p></div><span>{visible.length} properties</span></header>
 <div className="dp-filters"><label><span>Find a property</span><input aria-label="Find a property" placeholder="Property, plot or owner…" value={query} onChange={e=>setQuery(e.target.value)}/></label><label><span>Availability</span><select aria-label="Availability" value={filter} onChange={e=>chooseFilter(e.target.value)}><option value="all">All properties</option><option value="rent">City leases available</option><option value="sale">For sale</option><option value="mine">Your properties & leases</option><option value="storage">Garages & warehouses</option></select></label></div>
 <div className="dp-cards">{visible.map(p=>{
  const b=state.buildings.find(b=>b.plot_id===p.id),biz=state.businesses.find(b=>b.plot_id===p.id),type=state.building_types.find(t=>t.id===b?.building_type);
  const terms=state.lease_terms?.find(t=>t.template_id===p.template_id&&t.enabled),lease=state.leases?.find(l=>l.plot_id===p.id&&l.active),store=state.property_storage?.find(s=>s.plot_id===p.id);
  const rent=!!terms&&cityLeaseAvailable(p,state),owned=p.owner_id===state.player_id,mine=lease?.player_id===state.player_id;
  const status=owned?"Your property":mine?"Your lease":store?.can_access?"Collection locker":lease?"Leased":rent?"For lease":p.asking_price!==null||p.status==="available"?"For sale":p.status==="owned"?"Owned":p.status;
  return <article className="dp-card" key={p.id}><button className="dp-card-image" onClick={()=>onSelect(p.id)} aria-label={"View property "+p.code}><img src={propertyImage(p,state)} alt={(biz?.name??type?.name??"Property")+" in "+state.district.name} loading="lazy"/><span className={"dp-status "+(mine||owned?"yours":rent?"lease":status==="For sale"?"sale":"")}>{status}</span></button>
  <div className="dp-card-copy"><h3>{biz?.name??(type?.name?type.name+" · "+p.code:"Undeveloped plot "+p.code)}</h3><p className="dp-category"><GameIcon name={store?"inventory":"property"} size={17}/>{b?.building_type==="garage"?"Small garage":type?.name??p.zoning}</p><p className="dp-address"><GameIcon name="pin" size={15}/>{p.code} · {streets.find(s=>s.id===p.street_id)?.name??state.district.name}</p>
  <dl><div><dt>{lease?"Tenant":"Owner"}</dt><dd>{lease?.player_name??p.owner_name}</dd></div>
  {rent&&terms&&!lease?<div><dt>Prepaid rent</dt><dd>{money(terms.rent)} / {terms.term_hours}h</dd></div>:p.asking_price!==null||p.status==="available"?<div><dt>Asking price</dt><dd>{money(p.price)}</dd></div>:null}
  <div><dt>{store?"Storage":"Land area"}</dt><dd>{store?store.capacity.toLocaleString()+" units":p.size.toLocaleString()+" m²"}</dd></div>
  {store&&<div><dt>Crafting station</dt><dd>{store.station?"Installed":"Space available"}</dd></div>}</dl>
  <button className="dp-outline" onClick={()=>onSelect(p.id)}>{owned||mine||store?.can_access?"Manage property":rent&&!lease?"View lease":"View property"}<GameIcon name="arrow" size={17}/></button></div></article>;
 })}</div>{!visible.length&&<div className="dp-empty"><GameIcon name="property" size={36}/><h3>{filter==="mine"?"No properties here yet":"No matching properties"}</h3><p>{filter==="mine"?"Properties you own or lease in this district will appear here.":"Try another street or change your filters."}</p><button className="dp-outline" onClick={()=>{setStreet("all");chooseFilter("all");setQuery("");}}>Show all district properties</button></div>}
 </section><aside className="dp-intelligence"><section><header><h2>District businesses</h2><button onClick={()=>onSection("Businesses")}>View all →</button></header><p>{state.businesses.filter(b=>b.status==="open").length} businesses open in the district.</p><dl>{counts.map(([type,n])=><div key={type}><dt>{type}</dt><dd>{n}</dd></div>)}</dl></section>
 <section><header><h2>Strategic locations</h2></header>{state.sites.filter(s=>s.kind==="strategic").map(s=><button className="dp-site" key={s.id} onClick={()=>s.plot_id?onSelect(s.plot_id):onSection("Territory")}><GameIcon name="districts" size={24}/><span><strong>{s.name}</strong><small>{s.data.description??s.resource_type}</small></span><span>→</span></button>)}</section>
 <section><header><h2>District record</h2><button onClick={()=>onSection("Activity")}>View all →</button></header>{state.events.slice(0,4).map(e=><div className="dp-event" key={e.id}><i/><p>{e.description}<time dateTime={e.created_at}>{new Date(e.created_at).toLocaleDateString()}</time></p></div>)}{!state.events.length&&<p>No recorded activity yet.</p>}</section>
 <div className="dp-note"><GameIcon name="inventory" size={30}/><h3>A place for your next move.</h3><p>Lease city storage or build your own. Small garages hold essential stock. Warehouses give your operation room to grow.</p><Link href="/inventory">Open your inventory →</Link></div></aside></div></div>;
}
export function PropertyFacilities({p,state,act,busy}:{p:Plot;state:DistrictState;act:DistrictAction;busy:boolean}){
 const [confirm,setConfirm]=useState("");
 const store=state.property_storage?.find(s=>s.plot_id===p.id),terms=state.lease_terms?.find(t=>t.template_id===p.template_id&&t.enabled),
 lease=state.leases?.find(l=>l.plot_id===p.id&&l.active),mine=lease?.player_id===state.player_id,settings=state.property_settings;
 if(!store)return null;
 const run=async(a:string,payload:Record<string,unknown>={})=>{if(await act(a,{plot_id:p.id,...payload}))setConfirm("");};
 return <section className="dp-facilities"><h3>Storage & workspace</h3><p><strong>{store.capacity.toLocaleString()} storage units</strong>{store.station?" · "+store.station.space+" reserved for your crafting station":""}</p>
 {p.owner_type==="city"&&terms&&!lease&&cityLeaseAvailable(p,state)&&<div className="dp-lease-quote"><span className="dp-eyebrow">CITY LEASE</span><h3>{money(terms.rent)} <small>/ {terms.term_hours} hours</small></h3><p>Paid up front. Your lease gives you private storage access. Ownership stays with the city.</p><p>When it ends, deposits stop and your items stay in a private collection locker. Installed stations are retired when the property is leased again.</p><button className="district-gold" disabled={busy||state.cash<terms.rent||!store.enabled} onClick={()=>confirm==="rent"?void run("rent",{version:terms.version,rent:terms.rent}):setConfirm("rent")}>{confirm==="rent"?"Confirm city lease":"Lease this property"}</button>{confirm==="rent"&&<button className="dp-cancel" onClick={()=>setConfirm("")}>Go back</button>}</div>}
 {lease&&<p>{mine?"Your lease":"Leased to "+lease.player_name} · Ends {new Date(lease.ends_at).toLocaleString()}</p>}
 {mine&&terms&&<div className="dp-lease-actions"><button className="dp-outline" disabled={busy} onClick={()=>confirm==="renew"?void run("renew",{version:terms.version,rent:terms.rent}):setConfirm("renew")}>{confirm==="renew"?"Confirm renewal · "+money(terms.rent):"Extend lease · "+money(terms.rent)}</button><button className="dp-outline" disabled={busy} onClick={()=>confirm==="vacate"?void run("vacate"):setConfirm("vacate")}>{confirm==="vacate"?"Confirm return · no refund":"Return keys"}</button>{confirm==="vacate"&&<p>Collect your stock first. Prepaid rent and installation fees are not refunded.</p>}</div>}
 {store.can_access&&<PropertyStock key={store.building_id} buildingId={store.building_id} revision={JSON.stringify([store.capacity,store.enabled,store.can_store,store.station,lease?.ends_at])} busy={busy}/>}
 {store.can_access&&<Link className="district-gold" href={"/inventory?building="+store.building_id}>Open {store.can_store?"secure storage":"collection locker"} →</Link>}
 {store.can_store&&settings&&<div className="dp-station"><GameIcon name="tools" size={34}/><div><h3>Crafting station</h3>{store.station?<><p>Installed inside this property. {store.station.space} storage units reserved.</p><p>Learn blueprints and turn your materials into crafted goods.</p><Link className="district-gold" href={"/crafting?building="+store.building_id}>Open crafting menu →</Link><button className="dp-outline" disabled={busy} onClick={()=>confirm==="remove_station"?void run("remove_station"):setConfirm("remove_station")}>{confirm==="remove_station"?"Confirm removal · no refund":"Remove station"}</button></>:<><p>Fit a permanent workbench inside your garage or warehouse.</p><p>{money(settings.station_cost)} installation · {settings.station_space} storage units required.</p><button className="dp-outline" disabled={busy||state.cash<settings.station_cost||!store.enabled} onClick={()=>confirm==="install_station"?void run("install_station",{cost:settings.station_cost,space:settings.station_space}):setConfirm("install_station")}>{confirm==="install_station"?"Confirm installation":"Install crafting station"}</button></>}</div></div>}
 </section>;
}
