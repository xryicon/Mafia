import type {DistrictState,Auction} from "./districts";
export type Mine= {
 id:string;definition_id:string;plot_id:string;district_id:string;code:string;name:string;description:string;
 good_id:string;good_name:string;image_url:string;map_x:number;map_y:number;status:"open"|"closed"|"reserved";access_mode:"public"|"private";
 remaining:number;initial_reserve:number;hand_yield:number;hand_seconds:number;tool_wear:number;operation_yield:number;operation_seconds:number;
 operated_at:string;transport:string;survey_status:string;owner_type:string;owner_id:string|null;owner_name:string;base_price:number;tax_rate:number;
 active_shifts:number;ready_output:number;output_today:number;auction:(Omit<Auction,"seller_id">&{seller_id:string|null;city_sale:boolean;bidder_name:string|null})|null;
};
export type MiningState={
 world:DistrictState;sites:Mine[];can_manage:boolean;server_time:string;playable:boolean;season_end:string|null;
 tool:{durability:number};settings:Record<string,number>;
 shift:{id:string;mine_id:string;mine_name:string;code:string;good_id:string;good_name:string;quantity:number;respect:number;wear:number;ready_at:string;started_at:string}|null;
 inventory:{good_id:string;name:string;quantity:number}[];
 history:{id:number;mine_id:string;mine_name:string;good_id:string;good_name:string;quantity:number;source:string;created_at:string}[];
};
export const mineStatus=(m:Mine)=>m.auction?"Auction":m.status==="reserved"?"Reserved":m.status==="closed"?"Closed":m.remaining===0?"Exhausted":m.access_mode==="public"?"Public mining":m.owner_type==="player"?"Private operation":"Ready for auction";
export function mineNextBid(m:Mine,increment:number){return m.auction?Math.max(m.auction.minimum_bid,m.auction.bid+(m.auction.bidder_id?increment:0)):0;}
export const mineIcon=(id:string)=>id==="stone"||id==="limestone"?"mountain":"pickaxe";

