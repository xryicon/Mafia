// Browser fixture only. PostgreSQL tests verify timing, accounting and authorization separately.
export function scavWorld(game,bins,skills,onArrest=()=>{}){
 let patrols=[],catchSearch=false;
 const model={id:"sedan",name:"Dockside Sedan",sale_value:2200,enabled:true,version:1};
 let config={},ops={pursuit:null,island:false,cash_multiplier:1,event:null,vitals:{health:100,health_max:100,armour:0,armour_max:100},weapon:null,garages:[],vehicles:[],history:[],models:[model]};
 const vehicleRead=()=>({season_id:game.season.id,vehicles:ops.vehicles});
 const settle=()=>{const car={id:ops.pursuit.vehicle_id,name:model.name,sale_value:model.sale_value,building_id:ops.garages[0]?.id,code:"W25",garage_active:true,created_at:new Date().toISOString()};ops.pursuit=null;if(car.building_id){ops.vehicles.push(car);return {message:"Escaped. Dockside Sedan is secured in your garage.",stored:true};}game.player.cash+=model.sale_value;return {message:"Escaped. No garage space was available; Dockside Sedan was sold immediately for $2200.",cash:model.sale_value};};
 const resolve=()=>{if(!session?.pending||!catchSearch)return false;session.pending=null;onArrest();return true;};
 const setup=p=>{if(p.street){config={...config,...p};if(p.garage)ops.garages=[{id:"test-garage",code:"W25",district_name:"The Waterfront"}];if(p.weapon)ops.weapon={name:"Homemade pistol",ammo:30,condition:100,good_id:"homemade-pistol"};if(p.health!==undefined)ops.vitals.health=p.health;if(p.event)ops.event={id:"street-event",kind:p.event,node:2,expires_at:new Date(Date.now()+600000).toISOString()};if(p.lockpicks){let item=game.inventory.find(i=>i.good_id==="lockpick");if(item)item.quantity+=p.lockpicks;else game.inventory.push({good_id:"lockpick",quantity:p.lockpicks});}return;}catchSearch=!!p.catchSearch;patrols=p.enabled?[{id:"police-1",route_points:[[0,0],[4,0],[4,2],[0,2],[0,0]],epoch:1700000000,seconds_per_block:8,radius:.22}]:[];};
 let session=null;const maps=new Map(),requests=new Map(),recent=[];
 const settings={scavenging_foot_walk_seconds:10,scavenging_foot_sprint_percent:150,scavenging_input_lease_ms:500,scavenging_interaction_radius_percent:8,scavenging_foot_road_half_percent:13,scavenging_walk_seconds:1,scavenging_search_seconds:1,scavenging_lock_seconds:1,scavenging_restock_seconds:600,scavenging_car_success_percent:100,scavenging_lock_xp:25,scavenging_theft_success_percent:100,scavenging_combat_bullets:3,scavenging_escape_min_seconds:0};
 const read=()=>{const caught=resolve();const district=bins().read().districts.find(d=>d.id===session?.district_id);ops.island=district?.slug==='blackwater-island';ops.cash_multiplier=ops.island?3:1;return {session,targets:maps.get(session?.district_id)??[],streets:['Harbor Road','Warehouse Row','Dockside Avenue'],settings,recent,patrols,caught,operations:ops};};
 const motion=(action,p)=>{
  if(!session||p.district_id!==session.district_id)return{error:'Enter the district.'};
  const now=Date.now(),a=session.route_points[0],b=session.route_points.at(-1),duration=Date.parse(session.arrives_at)-Date.parse(session.departed_at),progress=duration>0?Math.max(0,Math.min(1,(now-Date.parse(session.departed_at))/duration)):1,origin=[a[0]+(b[0]-a[0])*progress,a[1]+(b[1]-a[1])*progress];
  if(action==='begin'){session.walk_controller=p.controller;session.walk_sequence=0;session.route_points=[origin];session.departed_at=session.arrives_at=new Date(now).toISOString();}
  else if(p.controller!==session.walk_controller)return{error:'Controller changed.'};
  else if(p.sequence>session.walk_sequence){session.walk_sequence=p.sequence;const length=Math.max(1,Math.hypot(p.dx,p.dy)),speed=p.sprint?10/1.5:10;const end=[Math.max(0,Math.min(4,origin[0]+p.dx/length*.5/speed)),Math.max(0,Math.min(2,origin[1]+p.dy/length*.5/speed))];session.route_points=[origin,end];session.departed_at=new Date(now).toISOString();session.arrives_at=new Date(now+(p.dx||p.dy?500:0)).toISOString();}
  return{server_time:new Date(now).toISOString(),session:{...session,pursuit:ops.pursuit},patrols};
 };
 function action(action,p){
  if(resolve())return {caught:true,message:"Caught by a police patrol."};
  if(requests.has(p.request_id))return requests.get(p.request_id);
  const data=bins().read();let result;const now=Date.now();
  if(action==='enter'){
   if(session?.pending||Date.parse(session?.arrives_at??'')>now)return{error:'Finish your current action.'};
   const district=data.districts.find(d=>d.id===p.district_id&&d.status!=='lockdown');if(!district)return{error:'District unavailable.'};
   if(session?.district_id!==p.district_id){if(!maps.has(p.district_id))maps.set(p.district_id,Array.from({length:10},(_,i)=>({id:'site-'+i,node:i+1,kind:i%3===2?'car':'bin',ready_at:null,vehicle:i%3===2?model:undefined})));session={district_id:p.district_id,node:0,path:[0],route_points:[[0,0]],departed_at:new Date(now).toISOString(),arrives_at:new Date(now).toISOString(),pending:null};}result={message:'Entered the streets.'};
  }else if(action==='move'){
   if(!session||session.pending)return{error:'Finish your current action.'};
   const destination=[p.x??p.node%5,p.y??Math.floor(p.node/5)];if(!destination.every(Number.isFinite)||destination[0]<0||destination[0]>4||destination[1]<0||destination[1]>2||(!Number.isInteger(destination[0])&&!Number.isInteger(destination[1])))return{error:'Choose a street.'};const from=session.route_points.at(-1);session.route_points=[from,[Math.round(from[0]),from[1]],[Math.round(from[0]),Math.round(destination[1])],[destination[0],Math.round(destination[1])],destination];session.path=[session.node];session.node=Math.round(destination[1])*5+Math.round(destination[0]);session.departed_at=new Date(now).toISOString();session.arrives_at=new Date(now+250).toISOString();result={message:'Walking.'};
  }else if(action==='event'){
   if(!ops.event||ops.event.kind==='sweep')return{error:'Event unavailable.'};session.pending={id:p.request_id,kind:'bin',mode:'event',started_at:new Date(now).toISOString(),ready_at:new Date(now+300).toISOString()};ops.event=null;result={message:'Investigating the street opportunity.'};
  }else if(action==='escape'){if(!ops.pursuit)return{error:'No pursuit.'};result=settle();
  }else if(action==='abandon'){ops.pursuit=null;result={message:'You abandoned the stolen car without a reward.'};
  }else if(action==='fight'){
   if(!ops.pursuit||!ops.weapon||ops.weapon.ammo<3)return{error:'Equip a working gun and compatible ammunition.'};ops.weapon.ammo-=3;ops.weapon.condition-=3;ops.vitals.health=Math.max(0,ops.vitals.health-30);
   if(!ops.vitals.health){ops.pursuit=null;onArrest();result={caught:true,message:'Police returned fire. You were sent to Blackwater Island.'};}else result={...settle(),message:'Police returned fire. You escaped injured.'};
  }else if(action==='sell_vehicle'){const car=ops.vehicles.find(v=>v.id===p.vehicle_id);if(!car)return{error:'Vehicle unavailable.'};ops.vehicles=ops.vehicles.filter(v=>v.id!==car.id);game.player.cash+=car.sale_value;result={message:'Vehicle sold.',cash:car.sale_value};
  }else if(action==='vehicle_model'){model.sale_value=p.sale_value;model.enabled=p.enabled;model.version++;result={message:'Vehicle model saved and audited.'};
  }else if(action==='search'||action==='steal'){
   const target=maps.get(session?.district_id)?.find(t=>t.id===p.target_id);
   if(!target||(Math.abs(target.node%5-session.route_points.at(-1)[0])+Math.abs(Math.floor(target.node/5)-session.route_points.at(-1)[1])>.08)||session.pending||Date.parse(session.arrives_at)>now||Date.parse(data.ready_at??'')>now||Date.parse(target.ready_at??'')>now)return{error:'Search unavailable.'};
   if(target.kind==='car'){const item=game.inventory.find(g=>g.good_id==='lockpick');if(!item?.quantity)return{error:'Carry a lockpick.'};item.quantity--;}
   session.pending={id:p.request_id,target_id:target.id,kind:target.kind,started_at:new Date(now).toISOString(),ready_at:new Date(now+300).toISOString(),success_percent:100,xp:25};if(action==='steal')session.pending.mode='theft';target.ready_at=new Date(now+600000).toISOString();result={message:'Searching.'};
  }else if(action==='finish'){
   if(!session?.pending||session.pending.id!==p.attempt_id||Date.parse(session.pending.ready_at)>now)return{error:'Search not ready.'};
   if(session.pending.mode==='theft'){
    ops.pursuit={id:session.pending.id,vehicle_id:session.pending.id,vehicle_name:model.name,started_at:new Date(now).toISOString(),grace_until:new Date(now+4000).toISOString(),deadline:new Date(now+90000).toISOString(),next_shot_at:new Date(now).toISOString(),exit_node:0,patrols,rules:settings};session.pending=null;result={message:'Engine running. Police alerted! Reach the escape marker or fight back.',pursuit:true};requests.set(p.request_id,result);return result;
   }
   result=bins().action('dive',{...p,district_id:session.district_id});if(result.error)return result;
   if(session.pending.kind==='car'){skills().award('lockpicking',session.pending.id,25,'Opened a parked car');result={...result,message:'Car opened. +25 Lockpicking XP.'};}
   recent.push({kind:session.pending.kind,opened:true,xp:session.pending.kind==='car'?25:0,created_at:new Date().toISOString()});session.pending=null;
  }else if(action==='cancel'){session.pending=null;result={message:'Search abandoned.'};}else return{error:'Unknown action.'};
  if(resolve())result={caught:true,message:"Caught by a police patrol."};
  requests.set(p.request_id,result);return result;
 }
 return{read,action,setup,resolve,vehicleRead,motion};
}
