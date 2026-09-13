import type {InventoryState} from "./inventory";
export type CraftRecipe={id:string;name:string;description:string;blueprint_good_id:string;output_good_id:string;output_units:number;seconds:number;materials:Record<string,number>;enabled:boolean;version:number};
export type CraftStation={id:string;building_id:string;code:string;name:string;district:string;slug:string;ready:boolean;image_url:string};
export type CraftJob={id:string;status:string;ready_at:string;starts_at:string;created_at:string;recipe_id:string;recipe_name:string;output_good_id:string;output_units:number;inputs:Record<string,number>;station_id:string;building_id:string;code:string};
export type CraftState={inventory:InventoryState;server_time:string;building_id:string|null;can_manage:boolean;settings:{queue_limit:number;max_batches:number};recipes:CraftRecipe[];learned:string[];stations:CraftStation[];jobs:CraftJob[]};
export const craftTime=(seconds:number)=>{const n=Math.max(0,Math.ceil(seconds));return n<60?n+"s":Math.floor(n/60)+"m "+n%60+"s";};
