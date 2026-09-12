import type {Ranking} from "@/lib/seasons";
export type PlayerProfile={
 player_id:string;handle:string;is_self:boolean;avatar_url:string;description:string;description_version:number|null;description_limit:number;
 joined_at:string;online:boolean;role:string;respect:number;level:number;title:string;respect_rank:number|null;
 gang:{id:string;name:string}|null;season:{id:string;name:string;status:string};current:Ranking[];previous:Ranking[];
 businesses:{id:string;name:string;kind:string;status:string;district:string|null;district_slug:string|null;plot_id:string|null;plot_code:string|null;image_url:string;href:string}[];
 business_total:number;plot_count:number;districts:{id:string;name:string;slug:string}[];server_time:string;
};
export const profileNumber=(value:number)=>Number(value).toLocaleString("en-GB");
