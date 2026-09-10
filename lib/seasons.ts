export type Season={id:string;name:string;status:"draft"|"open"|"locked"|"finalized"|"archived";starting_cash:number;starting_crates:number;starts_at:string|null;ends_at:string|null;locked_at:string|null;opened_at:string|null;archived_at:string|null;reset_at:string|null;hall_of_fame_places:number};
export type Ranking={player_id:string;handle:string;score:number;rank:number;metric?:string;label?:string;season_name?:string;season_id?:string};
export type Board={metric:string;label:string;enabled:boolean;direction:string;include_banned:boolean;hall_of_fame:boolean;available:boolean;description:string};
export type SeasonState={current_season_id:string;season:Season;seasons:Season[];boards:Board[];valuations:{good_id:string;unit_value:number}[];rankings:Ranking[];total:number;offset:number;metric:string;my_rank:Ranking|null;hall_of_fame:Ranking[];hall_total:number;can_manage:boolean;can_reset:boolean;server_time:string};
export function seasonPlayable(season:Pick<Season,"status"|"ends_at">,now:number){return season.status==="open"&&(!season.ends_at||Date.parse(season.ends_at)>now);}
export function resetConfirmation(name:string){return "RESET "+name;}
