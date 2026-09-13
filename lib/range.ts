import type {Season} from "./seasons";
export type RangeDifficulty="beginner"|"advanced";
export type RangeConfig={xp_version?:number;maximum_score?:number;completion_xp:number;required_rounds:number;cooldown_seconds:number;scoring_version:number;enabled:number;rounds:number;round_seconds:number;targets_per_round:number;move_vertical:number;bullseye_percent:number;move_amplitude:number;move_speed:number;radius_x:number;radius_y:number;hit_points:number;bullseye_points:number;fire_interval_ms:number;lag_tolerance_ms:number;actions_per_minute:number};
export type RangeMagazine={loaded:number;capacity:number;reserve:number;reloading:boolean;started_at:string|null;ready_at:string|null;reload_ms:number};
export type RangeRule={good_id:string;ammo_good_id:string;condition_max:number;wear_per_shot:number;enabled:boolean;version:number;magazine_capacity:number;reload_ms:number};
export type RangeWeapon={id:string;good_id:string;name:string;slot:string;raw_condition:number|null;condition:number|null;condition_max:number|null;wear_per_shot:number|null;enabled:boolean;ammo_good_id:string|null;ammo_name:string|null;magazine:RangeMagazine};
export type RangeShot={accuracy_percent:number;id:string;hit:boolean;points:number;round:number;lane:number|null;x:number;y:number;elapsed_ms:number;created_at:string};
export type RangeSession={accuracy_percent:number|null;score_xp:number;difficulty:RangeDifficulty|"legacy";xp_awarded:number;participated_rounds:number;cooldown_until:string|null;id:string;weapon_id:string;weapon_good_id:string;equipment_slot:string;seed:number;config:RangeConfig;weapon_rule:RangeRule;started_at:string;ends_at:string;status:"active"|"finished"|"stopped";shots:number;hits:number;score:number;streak:number;best_streak:number;last_shot_at:string|null;hit_targets:string[];last_shot:RangeShot|null};
export type RangeState={advanced_stats:{sessions:number;shots:number;average_accuracy:number|null;best_accuracy:number|null;xp_earned:number};difficulties:{id:RangeDifficulty;name:string;config:RangeConfig}[];cooldown_until:string|null;season:Season;server_time:string;config:RangeConfig;can_manage:boolean;weapons:RangeWeapon[];ammo:{id:string;good_id:string;name:string;quantity:number}|null;session:RangeSession|null;stats:{xp_earned:number;sessions:number;best_score:number;shots:number;hits:number;best_accuracy:number};recent:{accuracy_percent:number|null;difficulty:RangeDifficulty|"legacy";xp_awarded:number;id:string;score:number;hits:number;shots:number;status:string;started_at:string}[];leaders:{player_id:string;username:string;avatar_url:string|null;score:number}[];management:null|{weapons:RangeRule[];goods:{id:string;name:string;equipment_slots:string[]}[];settings:{key:string;value:number;minimum:number;maximum:number}[]}};
export const rangeTarget=(seed:number,round:number,lane:number,elapsed:number,c:RangeConfig)=>{const phase=((seed+round*53+lane*137)%628)/100,t=(elapsed%(c.round_seconds*1000))/1000*c.move_speed/100;return {x:50+(lane-(c.targets_per_round-1)/2)*(c.targets_per_round===2?40:30)+c.move_amplitude*Math.sin(t+phase),y:45+c.move_vertical*Math.sin(t*.7+phase),rx:c.radius_x,ry:c.radius_y};};
export const formatRangeAccuracy=(value:number|null|undefined)=>value==null?"—":value.toFixed(1).replace(/\.0$/,"");

export type RangeImpact={id:string;round:number;lane:number;x:number;y:number};
// Visual paper damage uses the accepted shot's time, never the later reply time.
// Scoring remains exclusively server-authoritative, including repeat hits and paper-edge misses.
export function rangeImpact(seed:number,shot:RangeShot,c:RangeConfig):RangeImpact|null{
 if(!Number.isFinite(shot.elapsed_ms)||!Number.isFinite(shot.x)||!Number.isFinite(shot.y))return null;
 const lanes=Array.from({length:c.targets_per_round},(_,i)=>c.targets_per_round-1-i);
 if(shot.lane!==null&&shot.lane>=0&&shot.lane<c.targets_per_round)lanes.unshift(shot.lane);
 for(const lane of lanes){
  const p=rangeTarget(seed,shot.round,lane,shot.elapsed_ms,c),x=(shot.x-p.x)*10,y=(shot.y-p.y)*6;
  if(Math.abs(x)<=p.rx*13.5&&y>=-p.ry*9.9&&y<=p.ry*8.7)return{id:shot.id,round:shot.round,lane,x,y};
 }
 return null;
}
