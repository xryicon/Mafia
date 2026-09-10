import type {GameState} from "@/lib/game";
import {money} from "@/lib/game";
import {GameIcon} from "@/components/game-icon";
export function MarketPulse({state,onChoose}:{state:GameState;onChoose:(id:string)=>void}){
 return <section className="market-pulse" aria-label="Player market overview"><div className="pulse-heading"><p className="eyebrow"><span className="green-dot"/> PLAYER MARKET</p><span>From the latest {state.market.length} open offers</span></div><div className="pulse-grid">{state.goods.map(g=>{
 const offers=state.market.filter(o=>o.good_id===g.id),units=offers.reduce((s,o)=>s+o.quantity,0),lowest=offers.length?Math.min(...offers.map(o=>o.unit_price)):null;
 return <button className={"pulse-card "+g.id} key={g.id} onClick={()=>onChoose(g.id)}><span className="pulse-commodity"><GameIcon name="market" size={16}/>{g.name}<GameIcon name="arrow" size={15}/></span><strong>{lowest===null?"No recent offers":money(lowest)}{lowest!==null&&<small> lowest ask / unit</small>}</strong><span className="pulse-foot">{units.toLocaleString("en-US")} units on offer <i>·</i> {offers.length} listing{offers.length===1?"":"s"}</span></button>;
 })}</div></section>;
}
