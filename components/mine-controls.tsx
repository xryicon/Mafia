"use client";
import {useState,type FormEvent} from "react";
import {money} from "@/lib/game";
import type {Mine,MiningState} from "@/lib/mining";
import type {MiningAction} from "./use-mining";
export function MineAuctionForm({site,data,busy,act}:{site:Mine;data:MiningState;busy:boolean;act:MiningAction}){
 const [price,setPrice]=useState(String(site.base_price)),[minutes,setMinutes]=useState(String(Math.max(data.settings.mining_auction_min_minutes,Math.min(data.settings.mining_auction_default_minutes,data.settings.mining_auction_max_minutes)))),[reason,setReason]=useState("");
 return <form className="mine-form mine-auction-form" onSubmit={e=>{e.preventDefault();void act("auction",{mine_id:site.id,price:Number(price),minutes:Number(minutes),reason});}}>
 <h3>Auction extraction rights</h3><p>The winner owns this seasonal property and its remaining reserves. Public access follows the city’s site rules.</p>
 <label>Minimum bid ($)<input required type="number" min="1" max="1000000000" value={price} onChange={e=>setPrice(e.target.value)}/></label>
 <label>Auction duration (minutes)<input required type="number" min={data.settings.mining_auction_min_minutes} max={data.settings.mining_auction_max_minutes} value={minutes} onChange={e=>setMinutes(e.target.value)}/></label>
 <label>Reason for this auction<input required minLength={3} maxLength={1000} value={reason} onChange={e=>setReason(e.target.value)}/></label>
 <p>Buyer tax: {site.tax_rate}%. Extraction pauses during bidding. A funded bid cannot be withdrawn.</p>
 <button className="market-gold" disabled={busy||!data.playable||site.status!=="open"||!!site.auction||site.active_shifts>0||site.remaining<1}>Start mine auction</button>
 {site.active_shifts>0&&<small>Wait for {site.active_shifts} active shift(s) to finish.</small>}
 </form>;
}
export function MineControls({site,data,busy,act}:{site:Mine;data:MiningState;busy:boolean;act:MiningAction}){
 async function save(e:FormEvent<HTMLFormElement>){
  e.preventDefault();const v=Object.fromEntries(new FormData(e.currentTarget)),numeric=["remaining","base_price","hand_yield","hand_seconds","tool_wear","operation_yield","operation_seconds","map_x","map_y"];
  const values:Record<string,unknown>={...v,mine_id:site.id};numeric.forEach(k=>values[k]=Number(v[k]));
  await act("manage",values,true);
 }
 return <section className="mine-admin-editor command-panel"><header className="command-panel-head"><h2>{site.code} · {site.name}</h2></header>
 <p className="mine-help">Site rules and opening defaults carry into future seasons. Current ownership and extraction history remain in the registry.</p>
 <form className="mine-form mine-edit-grid" onSubmit={save}>
 <label>Site name<input name="name" required minLength={3} maxLength={80} defaultValue={site.name}/></label>
 <label>Site status<select aria-label="Site status" name="status" defaultValue={site.status}><option value="open">Open</option><option value="closed">Closed</option><option value="reserved">Reserved for future release</option></select></label>
 <label>Mining access<select aria-label="Mining access" name="access_mode" defaultValue={site.access_mode}><option value="public">Public · all players with a pickaxe</option><option value="private">Private · property owner only</option></select></label>
 <label>Remaining resource units<input name="remaining" required type="number" min="0" max="100000000" defaultValue={site.remaining}/></label>
 <label>Property base value ($)<input name="base_price" required type="number" min="1" max="1000000000" defaultValue={site.base_price}/></label>
 <label>Public shift yield<input name="hand_yield" required type="number" min="1" max="1000" defaultValue={site.hand_yield}/></label>
 <label>Public shift duration (seconds)<input name="hand_seconds" required type="number" min="5" max="86400" defaultValue={site.hand_seconds}/></label>
 <label>Pickaxe wear per shift<input name="tool_wear" required type="number" min="1" max="10000" defaultValue={site.tool_wear}/></label>
 <label>Owner extraction per cycle<input name="operation_yield" required type="number" min="1" max="10000" defaultValue={site.operation_yield}/></label>
 <label>Owner cycle duration (seconds)<input name="operation_seconds" required type="number" min="30" max="86400" defaultValue={site.operation_seconds}/></label>
 <label>Map position X<input name="map_x" required type="number" min="90" max="1110" defaultValue={site.map_x}/></label>
 <label>Map position Y<input name="map_y" required type="number" min="80" max="560" defaultValue={site.map_y}/></label>
 <label>Transport access<input name="transport" maxLength={80} defaultValue={site.transport}/></label>
 <label>Survey status<input name="survey_status" maxLength={80} defaultValue={site.survey_status}/></label>
 <label className="mine-form-wide">Description<textarea name="description" maxLength={2000} defaultValue={site.description}/></label>
 <label className="mine-form-wide">Reason for this change<input name="reason" required minLength={3} maxLength={1000}/></label>
 <p className="mine-form-wide mine-help">Resource: {site.good_name}. Registered owner: {site.owner_name}. Current property value: {money(site.base_price)}. Saving resets the owner extraction clock.</p>
 <button className="market-gold mine-form-wide" disabled={busy||!!site.auction||site.active_shifts>0}>Save mine settings</button>
 {(!!site.auction||site.active_shifts>0)&&<p className="mine-form-wide mine-help">Finish the active auction or shifts before changing site rules.</p>}
 </form>
 {site.auction?<div className="mine-auction-admin"><h3>Auction in progress</h3><p>Current bid {money(site.auction.bid)} · {site.auction.bidder_name??"No bids yet"}</p><button className="market-outline" disabled={busy||!data.playable||!!site.auction.bidder_id} onClick={()=>void act("cancel_auction",{mine_id:site.id})}>Cancel unbid auction</button></div>:site.owner_type==="city"?<MineAuctionForm site={site} data={data} busy={busy} act={act}/>:<p className="mine-help">This mine belongs to {site.owner_name}. They control any resale auction.</p>}
 </section>;
}

