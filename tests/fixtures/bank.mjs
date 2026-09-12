import {randomUUID} from "node:crypto";
export function bankWorld(state){
 let balance=0,opened=null,entries=[],requests=new Map(),enabled=1,playable=true;
 const read=(offset=0)=>{const now=new Date(),today=now.toISOString().slice(0,10);
  return {season:state.season,server_time:now.toISOString(),playable,player:state.player,balance,opened_at:opened,settings:{bank_deposits_enabled:enabled,bank_max_transfer:1000000000},can_manage:state.permissions.includes("economy.manage"),offset,page_size:10,total:entries.length,history:entries.slice(offset,offset+10),totals:{deposited:entries.filter(e=>e.delta>0).reduce((a,e)=>a+e.delta,0),withdrawn:entries.filter(e=>e.delta<0).reduce((a,e)=>a-e.delta,0),transfers:entries.length},flow:Array.from({length:7},(_,i)=>{const day=new Date(Date.parse(today+"T00:00:00Z")-(6-i)*86400000).toISOString().slice(0,10);const rows=entries.filter(e=>e.created_at.startsWith(day));return {day,deposits:rows.filter(e=>e.delta>0).reduce((a,e)=>a+e.delta,0),withdrawals:rows.filter(e=>e.delta<0).reduce((a,e)=>a-e.delta,0)};})};
 };
 const action=(kind,p)=>{
  if(p.season_id!==state.season.id)return {error:"The season changed. Refresh the bank."};
  const key=JSON.stringify({kind,p}),prior=requests.get(p.request_id);if(prior)return prior.key===key?prior.result:{error:"This transfer reference was already used."};
  if(!playable)return {error:"Season is not open."};if(kind==="deposit"&&!enabled)return {error:"New deposits are paused. Withdrawals remain available."};
  if(!Number.isSafeInteger(p.amount)||p.amount<1||p.amount>1000000000)return {error:"Invalid amount."};
  const delta=kind==="deposit"?p.amount:-p.amount;
  if(delta>state.player.cash)return {error:"Not enough cash."};if(balance+delta<0)return {error:"Not enough money in your bank account."};
  state.player.cash-=delta;balance+=delta;opened??=new Date().toISOString();
  const entry={id:randomUUID(),delta,balance_after:balance,cash_after:state.player.cash,created_at:new Date().toISOString()};entries.unshift(entry);
  state.ledger.unshift({id:entry.id,delta:-delta,balance_after:state.player.cash,reason:"National Bank "+kind,created_at:entry.created_at});
  const result={message:kind==="deposit"?"Deposit complete. Your money is in the bank.":"Withdrawal complete. Your money is in your wallet.",receipt:entry};requests.set(p.request_id,{key,result});return result;
 };
 const setup=p=>{if(p.pause)enabled=0;if(p.close)playable=false;if(p.cash!==undefined)state.player.cash=p.cash;if(p.nextSeason)state.season={...state.season,id:randomUUID()};
  if(p.history){state.player.cash=2480000;for(let i=0;i<14;i++)action(i%3===2?"withdraw":"deposit",{season_id:state.season.id,request_id:randomUUID(),amount:1000+i*250});}
 };
 return {read,action,setup};
}
