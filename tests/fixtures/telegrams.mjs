// Isolated browser-test data. Never imported by application code.
import {randomUUID} from "node:crypto";
const other="33333333-3333-4333-8333-333333333333";
export function telegramWorld(playerId,season,officePlot){
 const thread={kind:"direct",other_avatar:"/art/command-portrait.jpg",can_send:true,id:"66666666-6666-4666-8666-666666666666",subject:"Steel shipment",other_id:other,other_name:"HarborJack",last_at:new Date().toISOString(),excerpt:"The docks are ready. Shall we make a deal?",unread:1,archived:false,starred:false};
 const state={player_id:playerId,cash:10000,season,server_time:new Date().toISOString(),limits:{subject:160,body:4000,group_name:60,group_members:50},members:[],invitations:[],gang:{id:"fixture-gang",name:"Cobalto Family"},unread:1,thread:null,threads:[thread],
 messages:[{id:"77777777-1111-4111-8111-111111111111",thread_id:thread.id,sender_id:other,recipient_id:playerId,sender_name:"HarborJack",body:"The docks are ready. Shall we make a deal?",created_at:new Date().toISOString()}],
 drafts:[],blocks:[],reports:[],office:{name:"Blackwater Telegram Office",description:"A direct line to the people who move this city.",fee:25,status:"open",available:true,owner_type:"city",owner_id:"99999999-9999-4999-8999-999999999999",owner_name:"Blackwater Port Authority",plot_id:officePlot,plot_code:"W06",district_name:"The Waterfront",district_slug:"the-waterfront",building_id:"building-office",business_id:"business-office",asking_price:15000,minimum_fee:0,maximum_fee:500,can_operate:false,can_manage:true,config:{minimum_fee:0,maximum_fee:500,default_fee:25,available:true,reset_sale_price:15000},history:[],locations:[],archives:[],stats:{today_count:1,week_count:1,season_count:1,today_revenue:25,week_revenue:25,season_revenue:25,average_per_day:1},hours:Array.from({length:24},(_,hour)=>({hour,count:hour===9?1:0}))}};
 const requests=new Map(),rooms=new Map();let ownAvatar="/art/command-portrait.jpg";
 return {read(p={}){
  const selected=state.threads.find(t=>t.id===p.p_thread);if(selected)selected.unread=0;
  return {...state,player_avatar:ownAvatar,members:rooms.get(p.p_thread)||[],thread:selected||null,unread:state.threads.reduce((n,t)=>n+t.unread,0),messages:state.messages.filter(m=>m.thread_id===p.p_thread).map(m=>({...m,sender_avatar:m.sender_id===playerId?ownAvatar:"/art/command-portrait.jpg"})),
   threads:state.threads.filter(t=>(!["groups","gang"].includes(p.p_folder)||t.kind===(p.p_folder==="groups"?"group":"gang"))).filter(t=>p.p_folder==="archive"?t.archived:p.p_folder==="starred"?t.starred:!t.archived)};
 },action(action,p,game){
  if(action==="send"){
   if(requests.has(p.request_id))return requests.get(p.request_id);
   if(!state.office.available)return {error:"Telegram service is currently unavailable."};
   if(Number(p.fee)!==state.office.fee)return {error:"The delivery fee changed. Review the new fee before sending."};
   let t=state.threads.find(t=>t.id===p.thread_id);
   if(!t){t={...thread,id:randomUUID(),subject:p.subject,unread:0};state.threads.unshift(t);}
   state.messages.push({id:randomUUID(),thread_id:t.id,sender_id:playerId,recipient_id:other,sender_name:"HarborBoss",body:p.body,created_at:new Date().toISOString()});
   t.excerpt=p.body;t.last_at=new Date().toISOString();game.player.cash-=state.office.fee;
   state.office.stats.today_count++;state.office.stats.week_count++;state.office.stats.season_count++;
   state.office.stats.today_revenue+=state.office.fee;state.office.stats.week_revenue+=state.office.fee;state.office.stats.season_revenue+=state.office.fee;
   state.drafts=state.drafts.filter(d=>d.id!==p.draft_id);
   const result={message:"Telegram delivered instantly.",thread_id:t.id};requests.set(p.request_id,result);return result;
  }
  if(action==="draft"){const id=p.id||randomUUID();state.drafts=state.drafts.filter(d=>d.id!==id);state.drafts.unshift({...p,id,updated_at:new Date().toISOString()});return {message:"Draft saved.",draft_id:id};}
  if(action==="delete_draft")state.drafts=state.drafts.filter(d=>d.id!==p.id);
  if(action==="archive"){const t=state.threads.find(t=>t.id===p.thread_id);t.archived=!t.archived;}
  if(action==="star"){const t=state.threads.find(t=>t.id===p.thread_id);t.starred=!t.starred;}
  if(action==="block")state.blocks.push({id:other,name:"HarborJack"});
  if(action==="unblock")state.blocks=state.blocks.filter(b=>b.id!==p.player_id);
  if(action==="report")state.reports.push({id:randomUUID(),message_id:p.message_id,status:"open",response:null,created_at:new Date().toISOString()});
  return {message:action==="report"?"Report submitted. Only this telegram can be inspected as evidence.":"Saved."};
 },avatar(url){ownAvatar=url||"/art/command-portrait.jpg";return ownAvatar;},
 acceptInvites(){for(const [id,members] of rooms){members.forEach(m=>{if(m.status==="invited")m.status="active";});const t=state.threads.find(t=>t.id===id);t.member_count=members.length;t.can_send=members.length>1;}},
 room(action,p){
  if(requests.has(p.request_id))return requests.get(p.request_id);
  let t=state.threads.find(t=>t.id===p.thread_id);
  if(action==="create"||action==="gang"){
   if(p.name==="BlockedGroup")return {error:"Your group ownership limit has been reached."};
   t={...thread,id:randomUUID(),other_id:null,other_name:action==="gang"?state.gang.name:p.name,kind:action==="gang"?"gang":"group",subject:action==="gang"?"Gang correspondence":"Private group",can_manage:action!=="gang",can_send:action==="gang",member_count:action==="gang"?2:1,unread:0,excerpt:"No telegrams yet",owner_id:playerId};
   state.threads.unshift(t);rooms.set(t.id,[{id:playerId,name:"HarborBoss",avatar_url:ownAvatar,status:"active",owner:true},...(action==="gang"?[{id:other,name:"HarborJack",status:"active",owner:false}]:[])]);
  }
  const members=rooms.get(t?.id)||[];
  if(action==="invite"){members.push({id:other,name:p.username,avatar_url:"/art/command-portrait.jpg",status:"invited",owner:false});}
  if(action==="remove"){rooms.set(t.id,members.filter(m=>m.id!==p.player_id));t.member_count=rooms.get(t.id).length;t.can_send=t.member_count>1;}
  if(action==="rename")t.other_name=p.name;
  if(action==="transfer"){t.can_manage=false;members.forEach(m=>m.owner=m.id===p.player_id);}
  if(action==="leave")state.threads=state.threads.filter(x=>x.id!==t.id);
  const result={message:action==="invite"?"Invitation sent.":action==="create"?"Group created. Invite your players.":action==="gang"?"Gang conversation opened.":"Group updated.",thread_id:t.id};
  requests.set(p.request_id,result);return result;
 },manage(action,p){
  if(["office","config"].includes(action)){state.office.fee=Number(p.fee);state.office.name=p.name;state.office.description=p.description;state.office.status=p.status;state.office.available=p.status==="open"&&(p.available??"true")==="true";}
  return {message:"Office updated. The change is recorded in audit history."};
 }};
}

