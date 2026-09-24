"use client";
import Link from "next/link";
import {useCallback,useEffect,useRef,useState} from "react";
import {createClient} from "@/lib/supabase/client";
import {money} from "@/lib/game";
import type {StoredVehicle} from "@/lib/street-operations";
import {GameIcon} from "./game-icon";
export function GarageVehicles({buildingId}:{buildingId:string}){
 const [data,setData]=useState<{season_id:string;vehicles:StoredVehicle[]}|null>(null),[notice,setNotice]=useState(""),[busy,setBusy]=useState(false),[retry,setRetry]=useState<Record<string,unknown>|null>(null),lock=useRef(false);
 const refresh=useCallback(async()=>{const r=await createClient().rpc("street_vehicle_state");if(r.error||!r.data)throw new Error("Vehicle storage could not refresh.");setData(r.data);},[]);
 useEffect(()=>{let active=true;void createClient().rpc("street_vehicle_state").then(r=>{if(active){if(r.error)setNotice("Vehicle storage could not load.");else setData(r.data);}});return()=>{active=false;};},[buildingId]);
 const sell=async(payload:Record<string,unknown>)=>{if(lock.current)return;lock.current=true;setBusy(true);let uncertain=true;try{const r=await createClient().rpc("scavenging_action",{p_action:"sell_vehicle",p_payload:payload});if(r.error)throw new Error("Response interrupted. Retry to confirm this same sale safely.");uncertain=false;setRetry(null);if(r.data?.error)throw new Error(r.data.error);setNotice(r.data?.message??"Vehicle sold.");window.dispatchEvent(new Event("blackwater:game"));await refresh();}catch(e){setNotice(e instanceof Error?e.message:"Sale unavailable.");if(uncertain)setRetry(payload);}finally{lock.current=false;setBusy(false);}};
 return <section className="dp-stock garage-vehicles"><header><h3>Vehicle bays</h3><Link href="/chop-shop">Chop shop ↗</Link><GameIcon name="truck" size={24}/></header>{notice&&<p role="status">{notice}</p>}{retry&&<button disabled={busy} onClick={()=>void sell(retry)}>Retry vehicle sale safely</button>}{!data?<button disabled={busy} onClick={()=>void refresh().catch(e=>setNotice(e.message))}>Refresh vehicles</button>:data.vehicles.filter(v=>v.building_id===buildingId).length?data.vehicles.filter(v=>v.building_id===buildingId).map(v=><article className="dp-stock-location" key={v.id}><GameIcon name="truck" size={26}/><div><strong>{v.name}</strong><p>{money(v.sale_value)} sale value</p></div><button className="dp-outline" disabled={busy||!!retry} onClick={()=>{if(window.confirm("Sell "+v.name+" for "+money(v.sale_value)+"?"))void sell({season_id:data.season_id,vehicle_id:v.id,request_id:crypto.randomUUID()});}}>Sell vehicle</button></article>):<p>No vehicles stored in this garage. Escape with a stolen car in Scavenging to fill a vehicle bay.</p>}</section>;
}
