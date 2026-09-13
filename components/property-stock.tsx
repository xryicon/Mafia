"use client";
import {useCallback,useEffect,useRef,useState} from "react";
import {createClient} from "@/lib/supabase/client";
import {useInventory} from "./use-inventory";
import {InventoryTransfer,type Move} from "./inventory-workspace";
import {CommodityArtwork} from "./commodity-artwork";
import {GameIcon} from "./game-icon";
import {kg,storeReady,type InventoryState,type InventoryGood,type Gear} from "@/lib/inventory";

export function PropertyStock({buildingId,revision,busy}:{buildingId:string;revision:string;busy:boolean}){
 const [data,setData]=useState<InventoryState|null>(null),[error,setError]=useState(""),[loading,setLoading]=useState(true);
 const load=useCallback(async()=>{setLoading(true);setError("");try{const r=await createClient().rpc("inventory_state");if(r.error||!r.data)throw new Error("Your property storage could not load.");setData(r.data);}catch(e){setError(e instanceof Error?e.message:"Storage unavailable.");}finally{setLoading(false);}},[]);
 useEffect(()=>{let live=true;void createClient().rpc("inventory_state").then(r=>{if(!live)return;if(r.error||!r.data)setError("Your property storage could not load.");else setData(r.data);setLoading(false);},()=>{if(live){setError("Your property storage could not load.");setLoading(false);}});return()=>{live=false;};},[buildingId]);
 if(!data)return <section className="dp-stock"><h3>Move goods</h3><p>{loading?"Opening your inventory and this property’s storage…":error}</p>{!loading&&<button className="dp-outline" onClick={()=>void load()}>Try loading storage again</button>}</section>;
 return <PropertyStockContents key={buildingId} initial={data} buildingId={buildingId} revision={revision} busy={busy}/>;
}
function PropertyStockContents({initial,buildingId,revision,busy}:{initial:InventoryState;buildingId:string;revision:string;busy:boolean}){
 const h=useInventory(initial),d=h.data,s=d.stores.find(s=>s.id===buildingId),last=useRef(revision),[side,setSide]=useState("carried"),[search,setSearch]=useState(""),[move,setMove]=useState<Move|null>(null);
 useEffect(()=>{if(last.current!==revision){last.current=revision;h.refresh();}},[revision]);
 const storing=side==="carried",raw=storing?d.carried:s?.contents??[];
 const goods=raw.map(i=>({good:d.goods.find(g=>g.id===i.good_id),quantity:i.quantity,gear:undefined as Gear|undefined,key:"good:"+i.good_id}));
 const gear=d.gear.filter(g=>storing?g.location!=="storage":g.location==="storage"&&g.building_id===buildingId).map(g=>({good:d.goods.find(i=>i.id===g.good_id),quantity:g.quantity,gear:g,key:"gear:"+g.id}));
 const items=[...goods,...gear].filter((i):i is {good:InventoryGood;quantity:number;gear:Gear|undefined;key:string}=>!!i.good&&i.quantity>0&&i.good.name.toLowerCase().includes(search.toLowerCase()));
 const allowed=!!s&&storeReady(s)&&d.playable&&d.season.id===initial.season.id&&(!storing||s.enabled&&!s.listed);
 return <section className="dp-stock" aria-label="Move goods at this property"><header><h3>Move goods</h3><button aria-label="Refresh property stock" disabled={h.busy||busy} onClick={()=>h.refresh()}><GameIcon name="refresh" size={18}/></button></header>
 {s?<><p className="dp-stock-location"><GameIcon name="inventory" size={19}/>{s.code} · {s.name}</p><div className="dp-stock-capacity"><span>Stored <strong>{s.used.toLocaleString()} / {s.capacity.toLocaleString()} units</strong></span><span>Carried <strong>{kg(d.capacity.used_grams)} / {kg(d.capacity.weight_grams)}</strong></span></div>
 <div className="dp-stock-switch" role="group" aria-label="Choose transfer direction"><button aria-pressed={storing} onClick={()=>{setSide("carried");setSearch("");}}>Inventory → storage</button><button aria-pressed={!storing} onClick={()=>{setSide("storage");setSearch("");}}>Storage → inventory</button></div>
 {!s.enabled&&<p className="dp-stock-hint">New deposits are closed. You can still collect your stored goods.</p>}{s.listed&&<p className="dp-stock-hint">Withdraw this property’s sale listing before depositing items.</p>}{!d.playable&&<p className="dp-stock-hint">Transfers resume when the season opens.</p>}
 <label className="dp-stock-search">Find an item<input aria-label="Find a storage item" placeholder="Search your goods…" value={search} onChange={e=>setSearch(e.target.value)}/></label>
 <div className="dp-stock-items">{items.map(item=><article key={item.key}><CommodityArtwork goodId={item.good.id} size={56}/><div><strong>{item.good.name}</strong><span>{item.quantity.toLocaleString()} {item.quantity===1?"unit":"units"}{item.gear?.location==="equipped"?" · Equipped":""}{item.gear?.condition!==null&&item.gear?.condition!==undefined?" · "+item.gear.condition+"% condition":""}</span></div><button disabled={busy||h.busy||!allowed} aria-label={(storing?"Store ":"Retrieve ")+item.good.name+(item.gear?" equipment":"")} onClick={()=>{h.clear();setMove({action:storing?"store":"retrieve",good:item.good,gear:item.gear,building:buildingId,season:d.season.id});}}>{storing?"Store":"Retrieve"} <GameIcon name="arrow" size={16}/></button></article>)}</div>
 {!items.length&&<p className="dp-stock-hint">{search?"No matching items.":storing?"Your carried inventory is empty.":"Nothing is stored here yet."}</p>}
 </>:<p>This property has no storage available to you. Expired lockers disappear once all your goods have been collected.</p>}
 {h.notice&&!move&&<p role={h.failed?"alert":"status"} className="district-notice">{h.notice}</p>}
 {move&&<InventoryTransfer move={move} h={h} fixedBuilding={buildingId} close={()=>setMove(null)}/>}
 </section>;
}
