import {randomUUID} from 'node:crypto';
export function chopWorld(state){
 const shop={id:'city-chop',owner_id:null,name:'City chop shop',district_id:'waterfront',district_name:'The Waterfront',district_slug:'the-waterfront',available:true,bays:2,occupied:0,queued:0,fee:350};let job=null;let vehicle=true;const receipts=new Map();let next=0;
 const read=()=>({season_id:state.season.id,player_id:state.player.id,settings:{chop_shop_cost:5000,chop_upgrade_cost:4000,chop_city_fee:350,chop_max_fee:300,chop_heat_per_part:4,chop_idle_seconds:300},shops:[shop],garages:[],vehicles:vehicle?[{id:'test-car',name:'Stolen coupe',sale_value:1500}]:[],job:structuredClone(job),location:{current:{id:'waterfront'},journey:null,jailed:false}});
 return {read,action(action,p){if(receipts.has(p.request_id))return receipts.get(p.request_id);let result={message:'Progress saved.'};
 if(action==='start'){if(!vehicle||job)return {error:'Car unavailable.'};vehicle=false;state.player.cash-=350;job={id:'test-job',shop_id:shop.id,vehicle_id:'test-car',vehicle_name:'Stolen coupe',status:'active',removed:[],part:null,step:0,token:randomUUID(),fee:350,queue_position:0};}
 else if(!job||job.id!==p.job_id)return {error:'Job unavailable.'};
 else if(action==='pause')job.status='paused';else if(action==='resume')job.status='active';
 else if(action==='select'){job.part=p.part;job.step=0;job.token=randomUUID();next=Date.now()+500;}
 else if(action==='work'){if(job.token!==p.token||job.step!==p.step||Date.now()<next)return {error:'Wrong removal step.'};if(job.step===5){job.removed.push(job.part);job.part=null;job.step=0;}else job.step++;job.token=randomUUID();next=Date.now()+500;}
 else if(action==='finish'){job=null;result={message:'Shell scrapped. Received 2 scrap metal.'};}
 receipts.set(p.request_id,result);return result;}};
}
