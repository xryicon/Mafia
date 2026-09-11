import type {GameState} from "./game";
export type Auction={id:string;season_id:string;seller_id:string;seller_name:string;good_id:string;district_id:string|null;quantity:number;starting_bid:number;current_bid:number;bidder_id:string|null;bidder_name:string|null;escrow:number;bid_count:number;increment:number;fee_percent:number;extension_seconds:number;status:"open"|"sold"|"unsold"|"cancelled";created_at:string;ends_at:string;completed_at:string|null;has_bid:boolean;fee_paid:number};
export type MarketState={game:GameState;auctions:Auction[];reserved_cash:number;reserved_stock:number;districts:{id:string;name:string}[];server_time:string};
export type MarketView="floor"|"auctions"|"mine"|"inventory"|"orders";
export function nextBid(a:Auction){return a.bid_count?a.current_bid+a.increment:a.starting_bid;}
export function auctionTime(end:string,now:number){
 const seconds=Math.max(0,Math.ceil((Date.parse(end)-now)/1000));
 if(!seconds)return "Closing";
 const days=Math.floor(seconds/86400),hours=Math.floor(seconds%86400/3600),minutes=Math.floor(seconds%3600/60);
 return days?days+"d "+hours+"h":hours?hours+"h "+minutes+"m":minutes+"m "+seconds%60+"s";
}
export const goodIcon=(id:string)=>id==="whiskey"?"barrel":id==="steel"?"steel":id==="silk"?"inventory":"inventory";

