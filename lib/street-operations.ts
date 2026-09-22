import type {PolicePatrol} from "./scavenging";
export type VehicleModel={id:string;name:string;sale_value:number;enabled:boolean;version:number};
export type StreetEvent={id:string;kind:"satchel"|"cache"|"sweep";node:number;expires_at:string};
export type Pursuit={id:string;vehicle_id:string;vehicle_name:string;started_at:string;grace_until:string;deadline:string;exit_node:number;patrols:PolicePatrol[];next_shot_at:string;rules:Record<string,number>};
export type StoredVehicle={id:string;name:string;sale_value:number;building_id:string;code:string;garage_active:boolean;created_at:string};
export type StreetOperations={pursuit:Pursuit|null;island:boolean;cash_multiplier:number;event:StreetEvent|null;vitals:{health:number;health_max:number;armour:number;armour_max:number};weapon:{name:string;ammo:number;condition:number;good_id:string}|null;garages:{id:string;code:string;district_name:string}[];vehicles:StoredVehicle[];history:{kind:string;details:{message:string;health?:number;damage?:number};created_at:string}[];models:VehicleModel[]};
export const eventNames={satchel:"Dropped courier satchel",cache:"Unattended supply cache",sweep:"Police sweep"};
