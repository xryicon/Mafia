// Browser interactions only; real PostgreSQL tests verify financial and equipment authority.
export function robberyWorld(game){
 const rules={enabled:true,bullet_min:0,bullet_max:100,steal_min:1,steal_max:80,victim_cooldown_seconds:1800,attacker_cooldown_seconds:300,presence_seconds:60,base_chance:50,min_chance:5,max_chance:95,skill_weight:20,accuracy_weight:20,power_weight:30,gear_weight:20,version:1};
 const gear=[{id:"homemade-pistol",name:"Homemade pistol",attack:20,defense:10,condition_max:100,version:1}];
 let weapon=null,targets=[],history=[],ready_at=null;const requests=new Map();
 const read=()=>({season_id:game.season.id,server_time:new Date().toISOString(),district_id:null,rules,factors:{power:game.player.xp,level:4,accuracy:62.5,attack:20,defense:10},weapon,available:true,ready_at,protected_until:null,targets,history,management:game.permissions.includes("roles.manage")?{gear}:null});
 const action=(kind,p)=>{
  if(kind==="configure"||kind==="gear"){if(!game.permissions.includes("roles.manage"))return {error:"Owner robbery permission required."};if(kind==="configure"){if(p.version!==rules.version)return {error:"Rules changed."};Object.assign(rules,p.rules);rules.version++;}else{const g=gear.find(g=>g.id===p.good_id);Object.assign(g,{attack:p.attack,defense:p.defense,condition_max:p.condition_max,version:g.version+1});rules.version++;}return {message:"Mugging settings saved and audited."};}
  const old=requests.get(p.request_id),key=JSON.stringify(p);if(old)return old.key===key?old.result:{error:"Request already used."};
  const t=targets.find(t=>t.id===p.target_id);if(!t||Date.parse(t.protected_until)>Date.now()||Date.parse(ready_at)>Date.now())return {error:"Robbery cooldown active."};if(!weapon||weapon.ammo<rules.bullet_max)return {error:"Not enough equipped bullets."};
  weapon.ammo-=3;weapon.condition-=3;game.player.cash+=250;ready_at=new Date(Date.now()+300000).toISOString();t.protected_until=new Date(Date.now()+1800000).toISOString();
  history.unshift({id:"robbery-1",created_at:new Date().toISOString(),succeeded:true,cash:250,bullets:3,attacking:true,other_name:t.handle});
  const result={message:"Mugging succeeded. Stole $250. Used 3 bullets.",cash:250,bullets:3,succeeded:true};requests.set(p.request_id,{key,result});return result;
 };
 const setup=p=>{weapon={id:"robbery-pistol",name:"Homemade pistol",good_id:"homemade-pistol",condition:100,condition_max:100,wear_per_shot:1,ammo:p.ammo??100,ammo_good_id:"homemade-bullets"};targets=[{id:"robbery-target",handle:"HarborJack",power:450,chance:63.5,avatar_url:null,protected_until:p.protected?new Date(Date.now()+1800000).toISOString():null}];};
 return {read,action,setup};
}
