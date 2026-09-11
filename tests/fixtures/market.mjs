// Isolated browser fixture. Economic invariants are tested against PostgreSQL separately.
import {randomUUID} from "node:crypto";
export function marketWorld(game,playerId){
 Object.assign(game.settings,{auction_min_minutes:5,auction_max_minutes:10080,auction_default_minutes:1440,auction_min_increment:10,auction_max_bid:1000000000,auction_extension_seconds:60,auction_listing_limit:20});
 const auctions=[{id:"88888888-aaaa-4888-8888-888888888888",season_id:game.season.id,seller_id:"33333333-3333-4333-8333-333333333333",seller_name:"HarborJack",good_id:"silk",district_id:null,quantity:10,starting_bid:300,current_bid:0,bidder_id:null,bidder_name:null,escrow:0,bid_count:0,increment:10,fee_percent:5,extension_seconds:60,status:"open",created_at:new Date().toISOString(),ends_at:new Date(Date.now()+3600000).toISOString(),completed_at:null,has_bid:false,fee_paid:0}];
 const receipts=new Map();
 const stock=(id,qty)=>{let row=game.inventory.find(i=>i.good_id===id);if(!row){row={good_id:id,quantity:0};game.inventory.push(row);}row.quantity+=qty;};
 const finish=a=>{if(a.status!=="open")return;a.status=a.bidder_id?"sold":"unsold";a.completed_at=new Date().toISOString();if(a.bidder_id===playerId)stock(a.good_id,a.quantity);if(a.seller_id===playerId){if(a.bidder_id)game.player.cash+=a.current_bid-Math.ceil(a.current_bid*a.fee_percent/100);else stock(a.good_id,a.quantity);}a.escrow=0;};
 return {expire(){for(const a of auctions)if(a.status==="open")a.ends_at=new Date(Date.now()-1000).toISOString();},
 read(districts){for(const a of auctions)if(a.status==="open"&&Date.parse(a.ends_at)<=Date.now())finish(a);return {game:{...game,server_time:new Date().toISOString()},auctions,reserved_cash:auctions.filter(a=>a.status==="open"&&a.bidder_id===playerId).reduce((n,a)=>n+a.escrow,0),reserved_stock:auctions.filter(a=>a.status==="open"&&a.seller_id===playerId).reduce((n,a)=>n+a.quantity,0),districts:districts.districts,server_time:new Date().toISOString()};},
 action(action,p){
 if(receipts.has(p.request_id))return receipts.get(p.request_id);
 let a=auctions.find(a=>a.id===p.auction_id),message="";
 if(action==="create"){
  const inv=game.inventory.find(i=>i.good_id===p.good_id);
  if(!inv||inv.quantity<p.quantity)return {error:"Not enough available goods."};
  inv.quantity-=p.quantity;a={...auctions[0],id:randomUUID(),seller_id:playerId,seller_name:game.player.handle,good_id:p.good_id,district_id:p.district_id??null,quantity:p.quantity,starting_bid:p.starting_bid,current_bid:0,bidder_id:null,bidder_name:null,escrow:0,bid_count:0,status:"open",created_at:new Date().toISOString(),ends_at:new Date(Date.now()+p.duration_minutes*60000).toISOString(),has_bid:false};auctions.unshift(a);message="Auction opened. Your goods are reserved.";
 }else if(!a)return {error:"Auction unavailable."};
 else if(action==="bid"){
  if(a.seller_id===playerId)return {error:"You cannot bid on your own auction."};
  const delta=p.amount-(a.bidder_id===playerId?a.escrow:0);
  if(a.status!=="open"||Date.parse(a.ends_at)<=Date.now()||p.amount<(a.bid_count?a.current_bid+a.increment:a.starting_bid)||game.player.cash<delta)return {error:"Bid unavailable."};
  game.player.cash-=delta;Object.assign(a,{current_bid:p.amount,bidder_id:playerId,bidder_name:game.player.handle,escrow:p.amount,bid_count:a.bid_count+1,has_bid:true});message="Bid placed. The full bid is held until you win or are outbid.";
 }else if(action==="cancel"){
  if(a.seller_id!==playerId||a.bid_count||a.status!=="open")return {error:"Cannot cancel this auction."};
  stock(a.good_id,a.quantity);a.status="cancelled";message="Auction withdrawn. Goods returned.";
 }else if(action==="settle"){finish(a);message="Auction settled.";}
 const result={message,auction_id:a.id};receipts.set(p.request_id,result);return result;
 }};
}

