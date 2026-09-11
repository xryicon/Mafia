export type Point=[number,number];
export type District={id:string;slug:string;name:string;description:string;tagline:string;district_type:string;image_url:string;industries:string[];strategic_importance:string;tax_rate:number;police_heat:number;property_value_index:number;property_trend:number;status:string;city_polygon:Point[];map_data:Record<string,unknown>;controller?:string;runtime_status?:string;available_plots?:number;active_businesses?:number;archived_at?:string|null};
export type Plot={id:string;season_id:string;template_id:string;district_id:string;code:string;polygon:Point[];size:number;zoning:string;status:string;owner_type:string;owner_id:string|null;owner_name:string;base_price:number;asking_price:number|null;price:number;tax:number;tax_rate:number|null;utility_level:number;infrastructure_level:number;build_capacity:number;strategic_type:string|null;version:number;offers_allowed:boolean;watched:boolean};
export type BuildingType={id:string;name:string;cost:number;construction_seconds:number;capacity_required:number;minimum_utility:number;minimum_infrastructure:number;business_type:string;good_id:string|null;batch_size:number;cycle_seconds:number;input_good_id:string|null;input_quantity:number;telegram_fee:number|null;active:boolean};
export type Building={id:string;plot_id:string;building_type:string;owner_id:string;level:number;condition:number;construction_status:string;cost:number;ready_at:string;built_at:string|null};
export type Business={id:string;plot_id:string;building_id:string;owner_type:string;owner_id:string;owner_name:string;name:string;business_type:string;status:string;description:string;buys:string[];sells:string[];telegram_fee:number|null;collected_at:string};
export type DistrictEvent={id:number;district_id:string;category:string;event_type:string;description:string;actor_id:string|null;actor_name:string;plot_id:string|null;business_id:string|null;gang_id:string|null;created_at:string};
export type Site={id:string;template_id:string;plot_id:string|null;name:string;kind:string;resource_type:string;data:Record<string,string|number>};
export type Auction={id:string;plot_id:string;seller_id:string;bidder_id:string|null;bid:number;minimum_bid:number;escrow:number;tax_rate:number;ends_at:string;status:string};
export type Offer={id:string;plot_id:string;buyer_id:string;seller_id:string;price:number;escrow:number;ends_at:string};
export type War={id:string;name:string;status:string;objectives:({name?:string;status?:string}|string)[];parties:{gang_id:string;name:string;side:string;supply:number;data:Record<string,string|number>}[];operations:{id:string;kind:string;description:string;status:string;created_at:string}[]};
export type DistrictState={
 districts:District[];district:District;season:{id:string;name:string;status:string};player_id:string;cash:number;gang_id:string|null;can_manage:boolean;server_time:string;
 plots:Plot[];buildings:Building[];businesses:Business[];sites:Site[];events:DistrictEvent[];territory:{controller_gang_id:string|null;controller_name:string;neutral_influence:number;fortification:number;status:string};
 gangs:{id:string;name:string;recruiting:boolean;founder:boolean}[];
 influence:{gang_id:string;name:string;influence:number}[];wars:War[];auctions:Auction[];offers:Offer[];
 sales:{id:string;plot_id:string;buyer_id:string;price:number;tax:number;method:string;created_at:string}[];
 buy_orders:{id:string;district_id:string;buyer_id:string;buyer_name:string;good_id:string;quantity:number;unit_price:number;escrow:number}[];price_comparisons:{good_id:string;local:number|null;city:number|null}[];
 market:import("./game").Listing[];trades:{id:number;good_id:string;quantity:number;unit_price:number;created_at:string}[];market_volume:number;
 building_types:BuildingType[];zoning:{id:string;name:string;allowed_buildings:string[]}[];goods:import("./game").Good[];jobs:import("./game").Job[];job_ready_at:string;
 settings:Record<string,number>;management:{districts:District[];templates:(Plot&{entity_id:string|null;building_type:string|null;business_name:string|null})[];site_templates:(Site&{district_id:string;plot_template_id:string|null})[];entities:{id:string;name:string}[];gangs:{id:string;name:string}[]}|null;
};
export const districtTabs=["Overview","Plots","Businesses","Resources","Market","Territory","Activity"] as const;
export type DistrictTab=typeof districtTabs[number];
export const points=(polygon:Point[])=>polygon.map(p=>p.join(",")).join(" ");
export function centroid(polygon:Point[]):Point{return [polygon.reduce((sum,p)=>sum+p[0],0)/polygon.length,polygon.reduce((sum,p)=>sum+p[1],0)/polygon.length];}
export function plotTone(p:Plot,auction?:Auction){return auction||p.status==="reserved"?"gold":p.status==="locked"?"gray":p.strategic_type?"red":p.owner_type==="player"?"blue":p.owner_id?"purple":"green";}
export function eligibleBuildings(p:Plot,state:DistrictState){return state.building_types.filter(b=>b.id!=="telegram"&&state.zoning.find(z=>z.id===p.zoning)?.allowed_buildings.includes(b.id)&&b.capacity_required<=p.build_capacity&&b.minimum_utility<=p.utility_level&&b.minimum_infrastructure<=p.infrastructure_level);}
