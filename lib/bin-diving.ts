export type LootItem="pickaxe"|"pistol_blueprint"|"bullet_blueprint";
export type BinRules={enabled:boolean;cooldown_seconds:number;cash_min:number;cash_max:number;cash_chance:number;pickaxe_chance:number;pistol_blueprint_chance:number;bullet_blueprint_chance:number;version:number};
export type BinReceipt={id:string;district_id:string;district_name:string;outcome:LootItem|"cash"|"nothing";cash:number;created_at:string;ready_at:string};
export type BinState={
 season:{id:string;name:string;status:string;ends_at:string|null};server_time:string;playable:boolean;can_manage:boolean;
 rules:BinRules;districts:{id:string;slug:string;name:string;tagline:string;image_url:string;police_heat:number;status:string}[];
 cash:number;inventory:Partial<Record<LootItem,number>>;tool_condition:number;tool_max:number;mining_shift:boolean;ready_at:string|null;history:BinReceipt[];
};
export const loot=[
 {id:"cash",name:"Loose cash",icon:"coins",description:"A little forgotten money. Straight into your wallet."},
 {id:"pickaxe",name:"Pickaxe",icon:"pickaxe",description:"Equip it and work a public site in Mines & Quarries."},
 {id:"pistol_blueprint",name:"Homemade pistol blueprint",icon:"blueprint",description:"A crafting collectible. Keep it for a future workshop."},
 {id:"bullet_blueprint",name:"Homemade bullet blueprint",icon:"blueprint",description:"A crafting collectible. Keep it for a future workshop."}
] as const;
export const emptyChance=(r:BinRules)=>Math.max(0,Math.round((100-r.cash_chance-r.pickaxe_chance-r.pistol_blueprint_chance-r.bullet_blueprint_chance)*100)/100);
export const binCountdown=(seconds:number)=>Math.floor(seconds/60)+":"+String(seconds%60).padStart(2,"0");
