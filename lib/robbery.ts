export type RobberyRules={enabled:boolean;bullet_min:number;bullet_max:number;steal_min:number;steal_max:number;victim_cooldown_seconds:number;attacker_cooldown_seconds:number;presence_seconds:number;base_chance:number;min_chance:number;max_chance:number;skill_weight:number;accuracy_weight:number;power_weight:number;gear_weight:number;version:number};
export type RobberyTarget={id:string;handle:string;avatar_url:string|null;power:number;chance:number;protected_until:string|null};
export type RobberyState={season_id:string;server_time:string;district_id:string|null;rules:RobberyRules;available:boolean;ready_at:string|null;protected_until:string|null;factors:{power:number;level:number;accuracy:number;attack:number;defense:number}|null;weapon:{id:string;name:string;good_id:string;condition:number;condition_max:number;wear_per_shot:number;ammo:number;ammo_good_id:string}|null;targets:RobberyTarget[];history:{id:string;created_at:string;succeeded:boolean;cash:number;bullets:number;attacking:boolean;other_name:string}[];management:null|{gear:{id:string;name:string;attack:number;defense:number;condition_max:number;version:number}[]}};
export const robberyRuleFields:[Exclude<keyof RobberyRules,"enabled"|"version">,string,number,number][]=[
 ["bullet_min","Minimum bullets used",0,100],["bullet_max","Maximum bullets used",0,100],
 ["steal_min","Minimum cash stolen (%)",1,80],["steal_max","Maximum cash stolen (%)",1,80],
 ["victim_cooldown_seconds","Victim protection (seconds)",60,86400],["attacker_cooldown_seconds","Attacker cooldown (seconds)",1,86400],
 ["base_chance","Base success chance (%)",0,100],["min_chance","Minimum success chance (%)",0,100],["max_chance","Maximum success chance (%)",0,100],
 ["skill_weight","Sharpshooting influence",0,100],["accuracy_weight","Advanced accuracy influence",0,100],["power_weight","Power influence",0,100],["gear_weight","Equipped gear influence",0,100]
];
