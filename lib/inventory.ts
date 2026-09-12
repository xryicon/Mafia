import type {Season} from "./seasons";
export type InventoryGood={id:string;name:string;category:string;description:string};
export type Stock={good_id:string;quantity:number};
export type Store={id:string;plot_id:string;building_type:string;name:string;code:string;district:string;district_slug:string;construction_status:string;ready_at:string;condition:number;capacity:number;enabled:boolean;version:number;listed:boolean;locked:boolean;used:number;contents:Stock[]};
export type InventoryState={season:Season;server_time:string;playable:boolean;player_id:string;cash:number;goods:InventoryGood[];carried:Stock[];stores:Store[];committed:(Stock&{destination:string})[];tool:{condition:number;maximum:number;working:boolean};max_transfer:number;history:{id:number;good_id:string;building_id:string|null;location:string;delta:number;quantity_after:number;reason:string;created_at:string}[];history_total:number;offset:number;management:null|{rules:{building_type:string;capacity:number;enabled:boolean;version:number}[];building_types:{id:string;name:string}[]}};
export const categoryNames:Record<string,string>={materials:"Materials",commodities:"Trade goods",tools:"Tools",blueprints:"Blueprints",weapons:"Weapons",ammunition:"Ammunition",armor:"Armor",medical:"Medical",consumables:"Consumables",other:"Other"};
export const countGood=(rows:Stock[],id:string)=>rows.reduce((n,x)=>n+(x.good_id===id?x.quantity:0),0);
export const storeReady=(s:Store)=>s.construction_status==="ready"&&!s.locked;
