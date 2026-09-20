// Browser fixture only. PostgreSQL tests verify timing, accounting and authorization separately.
export function scavWorld(game,bins,skills){
 let session=null;const maps=new Map(),requests=new Map(),recent=[];
 const settings={scavenging_walk_seconds:1,scavenging_search_seconds:1,scavenging_lock_seconds:1,scavenging_restock_seconds:600,scavenging_car_success_percent:100,scavenging_lock_xp:25};
 const read=()=>({session,targets:maps.get(session?.district_id)??[],streets:['Harbor Road','Warehouse Row','Dockside Avenue'],settings,recent});
 function action(action,p){
  if(requests.has(p.request_id))return requests.get(p.request_id);
  const data=bins().read();let result;const now=Date.now();
  if(action==='enter'){
   if(session?.pending||Date.parse(session?.arrives_at??'')>now)return{error:'Finish your current action.'};
   const district=data.districts.find(d=>d.id===p.district_id&&d.status!=='lockdown');if(!district)return{error:'District unavailable.'};
   if(session?.district_id!==p.district_id){if(!maps.has(p.district_id))maps.set(p.district_id,Array.from({length:10},(_,i)=>({id:'site-'+i,node:i+1,kind:i%3===2?'car':'bin',ready_at:null})));session={district_id:p.district_id,node:0,path:[0],route_points:[[0,0]],departed_at:new Date(now).toISOString(),arrives_at:new Date(now).toISOString(),pending:null};}result={message:'Entered the streets.'};
  }else if(action==='move'){
   if(!session||session.pending)return{error:'Finish your current action.'};
   const destination=[p.x??p.node%5,p.y??Math.floor(p.node/5)];if(!destination.every(Number.isFinite)||destination[0]<0||destination[0]>4||destination[1]<0||destination[1]>2||(!Number.isInteger(destination[0])&&!Number.isInteger(destination[1])))return{error:'Choose a street.'};const from=session.route_points.at(-1);session.route_points=[from,[Math.round(from[0]),from[1]],[Math.round(from[0]),Math.round(destination[1])],[destination[0],Math.round(destination[1])],destination];session.path=[session.node];session.node=Math.round(destination[1])*5+Math.round(destination[0]);session.departed_at=new Date(now).toISOString();session.arrives_at=new Date(now+250).toISOString();result={message:'Walking.'};
  }else if(action==='search'){
   const target=maps.get(session?.district_id)?.find(t=>t.id===p.target_id);
   if(!target||(target.node%5!==session.route_points.at(-1)[0]||Math.floor(target.node/5)!==session.route_points.at(-1)[1])||session.pending||Date.parse(session.arrives_at)>now||Date.parse(data.ready_at??'')>now||Date.parse(target.ready_at??'')>now)return{error:'Search unavailable.'};
   if(target.kind==='car'){const item=game.inventory.find(g=>g.good_id==='lockpick');if(!item?.quantity)return{error:'Carry a lockpick.'};item.quantity--;}
   session.pending={id:p.request_id,target_id:target.id,kind:target.kind,started_at:new Date(now).toISOString(),ready_at:new Date(now+300).toISOString(),success_percent:100,xp:25};target.ready_at=new Date(now+600000).toISOString();result={message:'Searching.'};
  }else if(action==='finish'){
   if(!session?.pending||session.pending.id!==p.attempt_id||Date.parse(session.pending.ready_at)>now)return{error:'Search not ready.'};
   result=bins().action('dive',{...p,district_id:session.district_id});if(result.error)return result;
   if(session.pending.kind==='car'){skills().award('lockpicking',session.pending.id,25,'Opened a parked car');result={...result,message:'Car opened. +25 Lockpicking XP.'};}
   recent.push({kind:session.pending.kind,opened:true,xp:session.pending.kind==='car'?25:0,created_at:new Date().toISOString()});session.pending=null;
  }else if(action==='cancel'){session.pending=null;result={message:'Search abandoned.'};}else return{error:'Unknown action.'};
  requests.set(p.request_id,result);return result;
 }
 return{read,action};
}
