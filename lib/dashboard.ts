import type {CityState} from "./city";
import type {GameState} from "./game";
import type {DistrictState, Point} from "./districts";
import type {SeasonState} from "./seasons";
import type {TelegramState, TelegramOffice} from "./telegrams";

export type DashboardMailbox={unread:number;office:Pick<TelegramOffice,"name"|"status"|"available"|"fee"|"district_name"|"district_slug"|"plot_id">};
export type DashboardData={game:GameState;city:CityState|null;district:DistrictState|null;season:SeasonState|null;mailbox:DashboardMailbox|null};
export function mailboxSummary(data:TelegramState):DashboardMailbox {
 const o=data.office;
 return {unread:data.unread,office:{name:o.name,status:o.status,available:o.available,fee:o.fee,district_name:o.district_name,district_slug:o.district_slug,plot_id:o.plot_id}};
}
export function respectProgress(xp:number,settings:Record<string,number>){
 const ranks=[{name:"Soldier",value:settings.rank_soldier},{name:"Caporegime",value:settings.rank_caporegime},{name:"Underboss",value:settings.rank_underboss}].filter(r=>Number.isFinite(r.value)).sort((a,b)=>a.value-b.value);
 const next=ranks.find(r=>r.value>xp),previous=[...ranks].reverse().find(r=>r.value<=xp);
 return {next,percent:next?Math.max(0,Math.min(100,(xp-(previous?.value??0))/(next.value-(previous?.value??0))*100)):100};
}
export function since(value:string,now:number){
 const minutes=Math.max(0,Math.floor((now-Date.parse(value))/60000));
 return minutes<1?"Now":minutes<60?minutes+"m":minutes<1440?Math.floor(minutes/60)+"h":Math.floor(minutes/1440)+"d";
}
export function until(value:string,now:number){
 const minutes=Math.max(0,Math.ceil((Date.parse(value)-now)/60000));
 return minutes===0?"Ready":minutes<60?minutes+"m":minutes<1440?Math.floor(minutes/60)+"h "+minutes%60+"m":Math.ceil(minutes/1440)+"d";
}
// Presentation coordinates for this illustration, not ownership or gameplay settings.
export const atlasAreas:{slug:string;name:string;subtitle:string;icon:string;color:string;label:Point;polygon:Point[]}[]=[
 {slug:"mines-and-quarries",name:"Mines & Quarries",subtitle:"Raw materials",icon:"pickaxe",color:"#a6926b",label:[163,131],polygon:[[12,100],[75,38],[202,22],[313,82],[334,139],[256,155],[160,167],[45,142]]},
 {slug:"old-town",name:"Old Town",subtitle:"Bars · Smuggling · Influence",icon:"businesses",color:"#bd7059",label:[258,243],polygon:[[40,210],[138,157],[283,151],[386,192],[470,240],[457,278],[380,291],[252,286],[132,279],[37,253]]},
 {slug:"downtown",name:"Downtown",subtitle:"Banking · Commerce · Power",icon:"bank",color:"#d0ab63",label:[635,254],polygon:[[515,169],[581,141],[650,158],[711,202],[787,221],[791,276],[731,315],[637,318],[559,283],[497,254]]},
 {slug:"the-waterfront",name:"The Waterfront",subtitle:"Shipping · Exports · Player trade",icon:"anchor",color:"#74a587",label:[339,393],polygon:[[31,320],[176,287],[313,298],[450,341],[521,352],[567,405],[645,463],[588,499],[469,479],[367,440],[224,465],[60,430],[8,377]]},
 {slug:"industrial-quarter",name:"Industrial Quarter",subtitle:"Factories · Production · Jobs",icon:"production",color:"#7e9daa",label:[971,268],polygon:[[858,158],[965,126],[1070,170],[1177,185],[1196,264],[1130,316],[980,350],[862,335],[822,276],[790,216]]},
 {slug:"blackwater-island",name:"Blackwater Island",subtitle:"Maximum security",icon:"bank",color:"#b1a786",label:[680,95],polygon:[[558,51],[641,27],[753,35],[820,82],[756,127],[641,116],[565,96]]},
 {slug:"drilling-shore",name:"Drilling Shore",subtitle:"Oil · Fuel · Strategic",icon:"rig",color:"#b89a65",label:[1053,470],polygon:[[948,422],[1030,364],[1147,396],[1169,479],[1090,525],[954,497]]}
];
