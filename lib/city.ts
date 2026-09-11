import type {CitySeason} from "./social";
export type CityState={avatar_url?:string;player_id:string;username:string;username_claimed:boolean;player:{cash:number;xp:number;power:number;rank:string;level:number};online_count:number;window_seconds:number;poll_seconds:number;season:CitySeason;permissions:string[];events:{id:string;description:string;cash_delta:number;created_at:string}[];server_time:string};
export type GangState={gangs:{id:string;name:string;members:number;respect:number;contribution:number;joined:boolean;rank:number}[];total:number;season:CitySeason;server_time:string};
export type GameView="overview"|"operations"|"market"|"businesses"|"inventory"|"ledger";
export function viewPath(view:GameView,good?:string){
 const path=view==="market"?"/market":view==="businesses"?"/properties":view==="operations"?"/districts":view==="inventory"?"/market?view=inventory":view==="ledger"?"/ledger":"/dashboard";
 return good?path+(path.includes("?")?"&":"?")+"good="+encodeURIComponent(good):path;
}
