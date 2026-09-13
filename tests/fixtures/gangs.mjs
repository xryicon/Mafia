import {randomUUID} from "node:crypto";
export function gangWorld(state,notify=()=>{}){
 const uid=state.player.id,other="33333333-3333-4333-8333-333333333333",third="44444444-4444-4444-8444-444444444444",gid="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
 const ranks=[{id:"underboss",label:"Underboss",priority:80,manage_members:true,review_requests:true},{id:"capo",label:"Capo",priority:60,manage_members:false,review_requests:false},{id:"soldier",label:"Soldier",priority:40,manage_members:false,review_requests:false},{id:"associate",label:"Associate",priority:20,manage_members:false,review_requests:false}];
 const member=(id,name,rank_id,is_owner=false)=>({id,name,rank_id,rank_label:is_owner?"Don / Gang leader":ranks.find(r=>r.id===rank_id).label,priority:ranks.find(r=>r.id===rank_id).priority,is_owner,version:1,avatar_url:"/art/command-portrait.jpg",respect:240,contribution:0,joined_at:new Date().toISOString(),online:true,can_edit:!is_owner});
 let g={id:gid,name:"Cobalto Family",description:"Loyalty is our currency. The waterfront is our home.",version:1,created_at:new Date().toISOString(),recruiting:true,leader:{id:uid,name:state.player.handle,avatar_url:"/art/command-portrait.jpg"},member_count:3,respect:18240,territories:[],members:[member(uid,state.player.handle,"associate",true),member(other,"HarborJack","soldier"),member(third,"IronRose","capo")],requests:[],application:null,events:[]};
 let role="owner",playable=true,balance=0,history=[],myId=gid,enabled=1;const requests=new Map();
 const read=(id,offset=0)=>{
  const is_member=role!=="visitor",is_owner=role==="owner",manage=is_owner||role==="underboss";
  const selected={...structuredClone(g),is_member,is_owner,can_manage:manage,can_review:manage,my_rank:is_owner?"Don / Gang leader":role==="underboss"?"Underboss":"Associate",members:is_member?g.members.map(m=>({...m,can_edit:manage&&!m.is_owner&&m.id!==uid&&(is_owner||m.priority<80)})):[],requests:manage?g.requests:[],bank:is_member?{balance,can_withdraw:is_owner,offset,page_size:10,total:history.length,my_deposits:history.filter(x=>x.delta>0&&x.actor_id===uid).reduce((a,x)=>a+x.delta,0),history:history.slice(offset,offset+10)}:null,events:is_member?g.events:[]};
  return {season:state.season,playable,player:{id:uid,name:state.player.handle,cash:state.player.cash},directory:[{id:g.id,name:g.name,description:g.description,members:g.members.length,respect:g.respect,contribution:0,joined:is_member,recruiting:g.recruiting,rank:1}],total:1,my_gang_id:is_member?g.id:null,selected:id&&id!==g.id?null:selected,ranks:ranks.map(r=>({...r,assignable:is_owner||manage&&r.priority<80})),settings:{district_gang_creation_cost:1000,gang_member_limit:50,gang_bank_max_transfer:1000000000,gang_bank_deposits_enabled:enabled,gang_request_cooldown_hours:24},server_time:new Date().toISOString()};
 };
 const action=(kind,p)=>{
  if(p.season_id!==state.season.id)return {error:"The season changed. Refresh the gang panel."};
  const key=JSON.stringify({kind,p}),prior=requests.get(p.request_id);if(prior)return prior.key===key?prior.result:{error:"This action reference was already used."};
  if(!playable)return {error:"Season is not open."};
  if(kind==="create"){g={...g,id:randomUUID(),name:p.name,description:"",members:[member(uid,state.player.handle,"associate",true)],events:[],requests:[]};role="owner";state.player.cash-=1000;}
  else if(kind==="request_join"){if(role!=="visitor")return {error:"You already belong to a gang."};if(!g.recruiting)return {error:"This gang is not recruiting."};if(!g.application||g.application.status!=="pending"){g.application={id:randomUUID(),status:"pending",created_at:new Date().toISOString()};notify(g.id,g.name,state.player.handle);}}
  else if(kind==="cancel_request"){g.application.status="cancelled";}
  else if(kind==="settings"){if(role!=="owner")return {error:"Only the gang leader can edit gang settings."};if(p.version!==g.version)return {error:"Gang settings changed. Refresh before saving."};g.description=p.description;g.recruiting=p.recruitment==="open";g.version++;}
  else if(kind==="rank"||kind==="remove"){const m=g.members.find(x=>x.id===p.player_id);if(!m||p.version!==m.version)return {error:"This member changed. Refresh before trying again."};if(kind==="rank"){m.rank_id=p.rank_id;m.rank_label=ranks.find(r=>r.id===p.rank_id).label;m.version++;}else g.members=g.members.filter(x=>x.id!==p.player_id);}
  else if(kind==="accept"||kind==="decline"){const a=g.requests.find(x=>x.id===p.application_id);if(!a)return {error:"This request is no longer pending."};if(kind==="accept")g.members.push(member(a.player_id,a.name,"associate"));g.requests=g.requests.filter(x=>x.id!==a.id);}
  else if(kind==="leave"){role="visitor";g.members=g.members.filter(x=>x.id!==uid);}
  else if(kind==="deposit"||kind==="withdraw"){
   if(role==="visitor")return {error:"Only current gang members can use this panel."};if(kind==="withdraw"&&role!=="owner")return {error:"Only the gang leader can withdraw gang funds."};
   if(kind==="deposit"&&!enabled)return {error:"Gang deposits are currently paused."};
   const delta=kind==="deposit"?p.amount:-p.amount;if(delta>state.player.cash)return {error:"Not enough cash, or this account is unavailable."};if(balance+delta<0)return {error:"Not enough money in the gang bank."};
   state.player.cash-=delta;balance+=delta;history.unshift({id:randomUUID(),actor_id:uid,name:state.player.handle,delta,balance_after:balance,created_at:new Date().toISOString()});
  }
  const message=kind==="request_join"?"Join request sent. The gang leader has been notified by Telegram.":kind==="rank"?"Member rank updated.":kind==="accept"?"Member accepted.":kind==="deposit"?"Gang deposit complete.":"Gang updated.";
  g.events.unshift({id:Date.now(),actor_id:uid,target_id:p.player_id??null,kind,description:message,created_at:new Date().toISOString()});
  const result={message,gang_id:g.id};requests.set(p.request_id,{key,result});return result;
 };
 return {read,action,setup(p){if(p.role)role=p.role;if(p.cash!==undefined)state.player.cash=p.cash;if(p.close)playable=false;if(p.pause)enabled=0;if(p.stale)g.members[1].version++;if(p.nextSeason)state.season={...state.season,id:randomUUID()};if(p.application){g.requests=[{id:randomUUID(),player_id:"99999999-9999-4999-8999-999999999999",name:"DockRunner",avatar_url:"/art/command-portrait.jpg",respect:120,created_at:new Date().toISOString()}];}if(p.history){state.player.cash=2480000;for(let i=0;i<14;i++)action("deposit",{season_id:state.season.id,request_id:randomUUID(),amount:1000+i*250});}}};
}
