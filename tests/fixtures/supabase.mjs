// Isolated browser-test service. Never imported by the application.
import http from "node:http";
import {skillsWorld} from "./skills.mjs";
import {rangeWorld} from "./range.mjs";
import {craftingWorld} from "./crafting.mjs";
import {propertyWorld} from "./property-leases.mjs";
import {readProfile,saveDescription} from "./profiles.mjs";
import {inventoryWorld} from "./inventory.mjs";
import {gangWorld} from "./gangs.mjs";
import {bankWorld} from "./bank.mjs";
import {refineryWorld} from "./refineries.mjs";
import {binWorld} from "./bin-diving.mjs";
import {scavWorld} from "./scavenging.mjs";
import {miningWorld} from "./mining.mjs";
import {marketWorld} from "./market.mjs";
import {telegramWorld} from "./telegrams.mjs";
import {districtWorld} from "./districts.mjs";
import { playerId, token, user } from "./identity.mjs";
const season={id:"55555555-5555-4555-8555-555555555555",name:"Founding Season",status:"open",starting_cash:10000,starting_crates:5,starts_at:null,ends_at:null,locked_at:null,opened_at:new Date().toISOString(),archived_at:null,reset_at:null,hall_of_fame_places:3};
const state = {season,
 jobs:[{"id":"docks","name":"Dock errand","district":"THE DOCKS","description":"Build connections.","reward":250,"xp":10,"cooldown":60},{"id":"warehouse","name":"Warehouse shift","district":"INDUSTRIAL QUARTER","description":"Keep goods moving.","reward":600,"xp":20,"cooldown":180},{"id":"courier","name":"Night courier","district":"OLD TOWN","description":"Work the night shift.","reward":1100,"xp":40,"cooldown":360}],
 settings:{closed_beta_starts_at_unix:1790877600,market_fee_percent:5,listing_limit:20,max_listing_quantity:1000,max_unit_price:1000000,offline_batches:24,rank_soldier:250,rank_caporegime:800,rank_underboss:2000},
 permissions:['assets.spawn','economy.manage','roles.manage','players.rename','tickets.manage','chat.delete','audit.view','evidence.view','seasons.manage','seasons.reset'],ledger:[],
 player:{id:playerId,handle:"HarborBoss",cash:10000,xp:0,job_ready_at:"2026-09-10T00:00:00Z",created_at:user.created_at},
 goods:[
  {id:"whiskey",name:"Whiskey crates",business_name:"Backroom distillery",business_cost:3000,batch_size:3,cycle_seconds:300},
  {id:"silk",name:"Silk bolts",business_name:"Textile workshop",business_cost:5000,batch_size:2,cycle_seconds:300},
  {id:"steel",name:"Steel bundles",business_name:"Dockside foundry",business_cost:8000,batch_size:2,cycle_seconds:300}],
 inventory:[{good_id:"whiskey",quantity:5}],businesses:[],
 market:[{id:"22222222-2222-4222-8222-222222222222",seller_id:"33333333-3333-4333-8333-333333333333",seller_handle:"Harbor-Jack",good_id:"silk",quantity:2,unit_price:100,status:"active",created_at:user.created_at}],
 my_listings:[],events:[{id:"welcome",description:"Arrived in Blackwater",cash_delta:10000,created_at:user.created_at}],
 server_time:new Date().toISOString(),
};
let districts=districtWorld(playerId,season,state.goods);
let telegrams=telegramWorld(playerId,season,districts.plots.find(p=>p.code==="W06").id);
let market=marketWorld(state,playerId);
let mining=miningWorld(state,districts,playerId);
let bins=binWorld(state,mining);
let scavenging=scavWorld(state,()=>bins,()=>skills);
let refineries=refineryWorld(state,playerId);
let bank=bankWorld(state);
let gangs=gangWorld(state,(...args)=>telegrams.recruitmentNotice(...args));
let inventory=inventoryWorld(state,()=>bins.read(),value=>mining.setDurability(value));
let properties=propertyWorld(districts,state,inventory);
let skills=skillsWorld(state);let crafting=craftingWorld(state,districts,inventory,skills.award,skills.rate);let range=rangeWorld(state,inventory,skills.award);
const breakoutInmateId="33333333-3333-4333-8333-333333333333";
let prisonSentence=null,prisonInmates=[],prisonAttempt=null,prisonBreakouts=0,prisonReward=50;
const lockpicks=()=>state.inventory.find(i=>i.good_id==="lockpick")?.quantity??0;
const publicAttempt=()=>prisonAttempt?{id:prisonAttempt.id,sentence_id:prisonAttempt.sentence_id,inmate_id:prisonAttempt.inmate_id,inmate_handle:prisonAttempt.inmate_handle,attempts_left:prisonAttempt.attempts_left,last_turn:prisonAttempt.last_turn,started_at:prisonAttempt.started_at,expires_at:prisonAttempt.expires_at}:null;
const expirePrisonAttempt=()=>{if(prisonAttempt&&Date.parse(prisonAttempt.expires_at)<=Date.now()){const inmate=prisonInmates.find(i=>i.sentence_id===prisonAttempt.sentence_id&&Date.parse(i.release_at)>Date.now());if(inmate)prisonSentence={id:"caught-timeout",reason:`Caught trying to break ${inmate.handle} out of prison`,started_at:new Date().toISOString(),release_at:inmate.release_at};prisonAttempt=null;}};
const prisonRead=()=>{expirePrisonAttempt();return {season_id:season.id,player_id:playerId,jailed:!!prisonSentence&&Date.parse(prisonSentence.release_at)>Date.now(),sentence:prisonSentence&&Date.parse(prisonSentence.release_at)>Date.now()?prisonSentence:null,district_slug:"blackwater-island",server_time:new Date().toISOString(),can_manage:state.permissions.includes("roles.manage"),reward_power:prisonReward,lockpicks:lockpicks(),inmates:prisonInmates.filter(i=>Date.parse(i.release_at)>Date.now()),attempt:publicAttempt(),leaderboard:prisonBreakouts?[{player_id:playerId,handle:state.player.handle,breakouts:prisonBreakouts,rank:1}]:[],my_breakouts:prisonBreakouts,my_rank:prisonBreakouts?1:null};};
const initialState=structuredClone(state);
const resetWorld=()=>{Object.assign(state,structuredClone(initialState));prisonSentence=null;prisonInmates=[];prisonAttempt=null;prisonBreakouts=0;prisonReward=50;delete state.profile_archived;market=marketWorld(state,playerId);districts=districtWorld(playerId,season,state.goods);telegrams=telegramWorld(playerId,season,districts.plots.find(p=>p.code==="W06").id);mining=miningWorld(state,districts,playerId);bins=binWorld(state,mining);scavenging=scavWorld(state,()=>bins,()=>skills);refineries=refineryWorld(state,playerId);bank=bankWorld(state);gangs=gangWorld(state,(...args)=>telegrams.recruitmentNotice(...args));inventory=inventoryWorld(state,()=>bins.read(),value=>mining.setDurability(value));properties=propertyWorld(districts,state,inventory);skills=skillsWorld(state);crafting=craftingWorld(state,districts,inventory,skills.award,skills.rate);range=rangeWorld(state,inventory,skills.award);};
const community={chat:[{id:"77777777-7777-4777-8777-777777777777",player_id:"33333333-3333-4333-8333-333333333333",username:"HarborJack",handle:"HarborJack",body:"The docks are open. Who is trading today?",role:"player",created_at:new Date().toISOString()}],cases:[],sanctions:[]};
const staff=()=>({permissions:state.permissions,players:[{id:playerId,handle:state.player.handle,role_id:"owner"}],sanctions:[],cases:community.cases,evidence:[],chat:community.chat,
 settings:[{key:"closed_beta_starts_at_unix",value:state.settings.closed_beta_starts_at_unix,minimum:0,maximum:2147483647},{key:"market_fee_percent",value:state.settings.market_fee_percent,minimum:0,maximum:100}],jobs:[],goods:state.goods,
 moderator_permissions:["players.warn"],permission_catalog:[{id:"players.warn",owner_only:false}],audit:[]});
let confirmationUsed=false;
const server = http.createServer(async(req,res) => {
 res.setHeader("Access-Control-Allow-Origin","http://localhost:3000");
 res.setHeader("Access-Control-Allow-Headers",req.headers["access-control-request-headers"] || "*");
 res.setHeader("Access-Control-Allow-Methods","GET, POST, OPTIONS");
 res.setHeader("Content-Type","application/json");
 if(req.method==="OPTIONS"){res.writeHead(204);res.end();return;}
 const url=new URL(req.url,"http://127.0.0.1:54329");
 const send=(status,data)=>{res.writeHead(status);res.end(JSON.stringify(data));};
 if(url.pathname==="/health"){send(200,{ok:true});return;}
 if(url.pathname==="/rest/v1/rpc/closed_beta_state"){send(200,{starts_at:new Date(state.settings.closed_beta_starts_at_unix*1000).toISOString(),server_time:new Date().toISOString()});return;}
 if(url.pathname==="/auth/v1/token"){let raw="";for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw||"{}");if(process.env.GAME_TEST_FIXTURE==="1"&&["fixture-reset","fixture-signup"].includes(p.auth_code)){send(200,{access_token:token,refresh_token:"test-refresh",expires_in:3600,token_type:"bearer",user});return;}send(400,{error:"invalid_grant",error_description:"Invalid test code"});return;}
 if(url.pathname==="/auth/v1/verify"&&process.env.GAME_TEST_FIXTURE==="1"){let raw="";for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw||"{}");if(p.type!=="email"||p.token_hash!=="a".repeat(64)||confirmationUsed){send(403,{code:"otp_expired",message:"Email link is invalid or has expired"});return;}confirmationUsed=true;send(200,{access_token:token,refresh_token:"test-refresh",expires_in:3600,token_type:"bearer",user});return;}
 if(url.pathname==="/auth/v1/resend"&&process.env.GAME_TEST_FIXTURE==="1"){send(200,{});return;}
 if(url.pathname==="/rest/v1/rpc/username_available"){let raw="";for await(const chunk of req)raw+=chunk;const {candidate}=JSON.parse(raw);send(200,{available:candidate.toLowerCase()!=="harborboss"});return;}
 if(req.headers.authorization!=="Bearer "+token){send(401,{code:"bad_jwt",message:"Invalid session"});return;}
 if(url.pathname==="/__reset_confirmation"&&process.env.GAME_TEST_FIXTURE==="1"){confirmationUsed=false;send(200,{ok:true});return;}
 if(url.pathname==="/auth/v1/user"){send(200,user);return;}



 if(url.pathname==="/__prison_setup"&&process.env.GAME_TEST_FIXTURE==="1"){let raw="";for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw||"{}");
  if(p.visitor){prisonSentence=null;prisonInmates=[{sentence_id:"prison-target",player_id:breakoutInmateId,handle:"HarborJack",reason:"Target sentence",started_at:new Date().toISOString(),release_at:new Date(Date.now()+(p.seconds??600)*1000).toISOString()}];let row=state.inventory.find(i=>i.good_id==="lockpick");if(!row){row={good_id:"lockpick",quantity:0};state.inventory.push(row);}row.quantity=p.lockpicks??1;}
  else prisonSentence={id:"prison-test",reason:"Serving a test sentence",started_at:new Date().toISOString(),release_at:new Date(Date.now()+p.seconds*1000).toISOString()};send(200,{ok:true});return;}
 if(url.pathname==="/__prison_break_expire"&&process.env.GAME_TEST_FIXTURE==="1"){if(prisonAttempt)prisonAttempt.expires_at=new Date(Date.now()-1000).toISOString();send(200,{ok:true});return;}
 if(url.pathname==="/rest/v1/rpc/prison_state"){send(200,prisonRead());return;}
 if(url.pathname==="/rest/v1/rpc/prison_break_action"){let raw="";for await(const chunk of req)raw+=chunk;const {p_action:a,p_payload:p}=JSON.parse(raw||"{}");
  if(a==="start"){const inmate=prisonInmates.find(i=>i.sentence_id===p.sentence_id&&Date.parse(i.release_at)>Date.now());if(!inmate){send(200,{error:"That inmate is no longer available for a breakout."});return;}const row=state.inventory.find(i=>i.good_id==="lockpick");if(!row?.quantity){send(200,{error:"You need a lockpick."});return;}row.quantity--;prisonAttempt={id:"breakout-attempt",sentence_id:inmate.sentence_id,inmate_id:inmate.player_id,inmate_handle:inmate.handle,target_angle:12,attempts_left:5,last_turn:0,started_at:new Date().toISOString(),expires_at:new Date(Date.now()+90000).toISOString()};send(200,{message:"Lockpick committed. Find the hidden angle before the guard reaches you.",outcome:"started",attempt:publicAttempt()});return;}
  if(a==="tension"){if(!prisonAttempt){send(200,{error:"This lock is no longer active."});return;}const inmate=prisonInmates.find(i=>i.sentence_id===prisonAttempt.sentence_id);const distance=Math.abs(Number(p.angle)-prisonAttempt.target_angle);if(distance<=6){state.player.xp+=prisonReward;prisonBreakouts++;skills.award("lockpicking","breakout-"+prisonBreakouts,prisonReward,"Opened a Blackwater Island prison lock");prisonInmates=prisonInmates.filter(i=>i.sentence_id!==prisonAttempt.sentence_id);const reward=prisonReward;prisonAttempt=null;send(200,{message:`The lock opened. The inmate is free and you earned +${reward} power.`,outcome:"success",turn:90,attempts_left:4,reward_power:reward});return;}const turn=Math.max(8,Math.min(75,78-Math.round(distance*.75)));prisonAttempt.attempts_left--;prisonAttempt.last_turn=turn;if(prisonAttempt.attempts_left<=0){prisonSentence={id:"caught-sentence",reason:`Caught trying to break ${inmate.handle} out of prison`,started_at:new Date().toISOString(),release_at:inmate.release_at};prisonAttempt=null;send(200,{message:"Caught. You are now serving the same remaining time as the inmate you tried to free.",outcome:"caught",turn,attempts_left:0,release_at:inmate.release_at});return;}send(200,{message:turn>=60?"Almost there. The cylinder nearly turned.":turn>=35?"The lock moved. Adjust the angle.":"The pick barely caught. Try farther away.",outcome:"continue",turn,attempts_left:prisonAttempt.attempts_left});return;}
  send(200,{error:"Choose a supported prison-break action."});return;
 }
 if(url.pathname==="/rest/v1/rpc/prison_manage"){let raw="";for await(const chunk of req)raw+=chunk;const {p_action:a,p_payload:p}=JSON.parse(raw||"{}");
  if(!state.permissions.includes("roles.manage")){send(403,{message:"Owner permission required."});return;}
  if(a==="list"){send(200,{sentences:prisonRead().jailed?[{...prisonSentence,player_id:playerId,handle:state.player.handle}]:[],reward_power:{value:prisonReward,minimum:0,maximum:100000}});return;}
  if(a==="configure_breakout"){prisonReward=Number(p.reward_power);send(200,{message:"Prison-break power reward saved.",reward_power:prisonReward});return;}
  if(a==="jail")prisonSentence={id:"prison-owner",reason:p.reason,started_at:new Date().toISOString(),release_at:new Date(Date.now()+Number(p.minutes)*60000).toISOString()};
  if(a==="release")prisonSentence=null;send(200,{message:a==="release"?"Player released from Blackwater Island Prison.":"Player transferred to Blackwater Island Prison."});return;
 }
 if(url.pathname==="/rest/v1/rpc/vitals_state"){send(200,{season_id:season.id,health:100,health_max:100,health_cap:120,armour:0,armour_max:100,decay_seconds:60,server_time:new Date().toISOString()});return;}
 if(url.pathname==="/__skills_setup"&&process.env.GAME_TEST_FIXTURE==="1"){let raw="";for await(const chunk of req)raw+=chunk;skills.setup(JSON.parse(raw||"{}"));send(200,{ok:true});return;}
 if(url.pathname==="/rest/v1/rpc/skills_state"){send(200,skills.read());return;}
 if(url.pathname==="/rest/v1/rpc/skills_manage"){let raw="";for await(const chunk of req)raw+=chunk;send(200,skills.manage(JSON.parse(raw||"{}").p_payload));return;}
 if(url.pathname.startsWith("/rest/v1/rpc/range_")){let raw="";for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw||"{}");send(200,url.pathname.endsWith("range_state")?range.read():url.pathname.endsWith("range_manage")?range.manage(p.p_action,p.p_payload):range.action(p.p_action,p.p_payload));return;}
 if(url.pathname==="/__range_setup"&&process.env.GAME_TEST_FIXTURE==="1"){let raw="";for await(const chunk of req)raw+=chunk;range.setup(JSON.parse(raw||"{}"));send(200,{ok:true});return;}
 if(url.pathname.startsWith("/rest/v1/rpc/crafting_")){let raw="";for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw||"{}");send(200,url.pathname.endsWith("crafting_state")?crafting.read(p.p_building):url.pathname.endsWith("crafting_manage")?crafting.manage(p.p_payload):crafting.action(p.p_action,p.p_payload));return;}
 if(url.pathname==="/__crafting_setup"&&process.env.GAME_TEST_FIXTURE==="1"){let raw="";for await(const chunk of req)raw+=chunk;crafting.setup(JSON.parse(raw||"{}"));send(200,{ok:true});return;}
 if(url.pathname.startsWith("/rest/v1/rpc/property_")){let raw="";for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw||"{}");send(200,url.pathname.endsWith("property_manage")?properties.manage(p.p_action,p.p_payload):properties.action(p.p_action,p.p_payload));return;}
 if(url.pathname.startsWith("/rest/v1/rpc/inventory_")){let raw="";for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw||"{}");send(200,url.pathname.endsWith("inventory_state")?inventory.read(p.p_offset):url.pathname.endsWith("inventory_manage")?inventory.manage(p.p_action,p.p_payload):inventory.action(p.p_action,p.p_payload));return;}
 if(url.pathname==="/__inventory_setup"&&process.env.GAME_TEST_FIXTURE==="1"){let raw="";for await(const chunk of req)raw+=chunk;const setup=JSON.parse(raw||"{}");if(setup.full){mining.activate();for(const g of refineries.read().goods)if(!state.goods.some(x=>x.id===g.id))state.goods.push(g);}inventory.setup(setup);send(200,{ok:true});return;}
 if(url.pathname==="/rest/v1/rpc/gang_workspace"||url.pathname==="/rest/v1/rpc/gang_action"){let raw="";for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw||"{}");send(200,url.pathname.endsWith("gang_workspace")?gangs.read(p.p_gang,p.p_offset):gangs.action(p.p_action,p.p_payload));return;}
 if(url.pathname==="/__gang_setup"&&process.env.GAME_TEST_FIXTURE==="1"){let raw="";for await(const chunk of req)raw+=chunk;gangs.setup(JSON.parse(raw||"{}"));send(200,{ok:true});return;}
 if(url.pathname.startsWith("/rest/v1/rpc/bank_")){let raw="";for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw||"{}");send(200,url.pathname.endsWith("bank_state")?bank.read(p.p_offset):bank.action(p.p_action,p.p_payload));return;}
 if(url.pathname==="/__bank_setup"&&process.env.GAME_TEST_FIXTURE==="1"){let raw="";for await(const chunk of req)raw+=chunk;bank.setup(JSON.parse(raw||"{}"));send(200,{ok:true});return;}
 if(url.pathname.startsWith("/rest/v1/rpc/telegram_")){
  let raw="";for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw||"{}");
  if(url.pathname.endsWith("telegram_state"))send(200,{...telegrams.read(p),cash:state.player.cash});
  else if(url.pathname.endsWith("telegram_room_action"))send(200,telegrams.room(p.p_action,p.p_payload));
  else if(url.pathname.endsWith("telegram_action"))send(200,telegrams.action(p.p_action,p.p_payload,state));
  else if(url.pathname.endsWith("telegram_manage"))send(200,telegrams.manage(p.p_action,p.p_payload));
  else send(400,{message:"Evidence unavailable."});
  return;
 }
 if(url.pathname==="/rest/v1/rpc/district_state"){let raw="";for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw||"{}");send(200,{...mining.district(p.p_slug),server_time:new Date().toISOString()});return;}
 if(url.pathname.startsWith('/rest/v1/rpc/refinery_')){let raw='';for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw||'{}');send(200,url.pathname.endsWith('refinery_state')?refineries.read():refineries.action(p.p_action,p.p_payload));return;}
 if(url.pathname==='/__refinery_setup'&&process.env.GAME_TEST_FIXTURE==='1'){let raw='';for await(const chunk of req)raw+=chunk;refineries.setup(JSON.parse(raw||'{}'));send(200,{ok:true});return;}
 if(url.pathname==='/rest/v1/rpc/scavenging_action'){let raw='';for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw||'{}');send(200,scavenging.action(p.p_action,p.p_payload));return;}
 if(url.pathname.startsWith('/rest/v1/rpc/bin_diving_')){let raw='';for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw||'{}');send(200,url.pathname.endsWith('bin_diving_state')?{...bins.read(),scavenging:scavenging.read()}:bins.action(p.p_action,p.p_payload));return;}
 if(url.pathname==='/__bin_setup'&&process.env.GAME_TEST_FIXTURE==='1'){let raw='';for await(const chunk of req)raw+=chunk;bins.setup(JSON.parse(raw||'{}'));send(200,{ok:true});return;}
 if(url.pathname.startsWith('/rest/v1/rpc/mining_')){let raw='';for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw||'{}');if(url.pathname.endsWith('mining_state'))send(200,mining.read());else send(200,mining.action(url.pathname.endsWith('mining_manage')?'manage':p.p_action,p.p_payload));return;}
 if(url.pathname==='/__mining_equipped'&&process.env.GAME_TEST_FIXTURE==='1'){mining.equip();send(200,{ok:true});return;}
 if(url.pathname==='/__finish_mining'&&process.env.GAME_TEST_FIXTURE==='1'){mining.finish();send(200,{ok:true});return;}
 if(url.pathname==='/__mining_player'&&process.env.GAME_TEST_FIXTURE==='1'){mining.player();send(200,{ok:true});return;}
 if(url.pathname==="/rest/v1/rpc/district_action"){
  let raw="";for await(const chunk of req)raw+=chunk;const {p_action:action,p_payload:p}=JSON.parse(raw),plot=districts.plots.find(x=>x.id===p.plot_id);
  if(action==="buy"){const total=plot.price+Math.ceil(plot.price*plot.tax/100);if(plot.status!=="available"||state.player.cash<total){send(200,{error:"Plot unavailable or insufficient cash."});return;}state.player.cash-=total;Object.assign(plot,{status:"owned",owner_type:"player",owner_id:playerId,owner_name:state.player.handle,version:plot.version+1});}
  if(action==="watch")plot.watched=!plot.watched;
  if(action==="sell"){plot.asking_price=Number(p.price);plot.offers_allowed=p.offers_allowed;}
  if(action==="build"){const type=districts.building_types.find(t=>t.id===p.building_type);state.player.cash-=type.cost;districts.buildings.push({id:"new-building",plot_id:plot.id,building_type:type.id,owner_id:playerId,level:1,condition:100,construction_status:"building",cost:type.cost,ready_at:new Date(Date.now()+300000).toISOString()});}
  if(action==="job"){state.player.cash+=250;state.player.xp+=10;districts.job_ready_at=new Date(Date.now()+60000).toISOString();}
  districts.events.unshift({id:Date.now(),district_id:districts.district.id,category:action==="buy"?"property":"system",event_type:action,description:action==="buy"?plot.code+" sold to "+state.player.handle:"District updated",actor_id:playerId,actor_name:state.player.handle,plot_id:plot?.id??null,business_id:null,gang_id:null,created_at:new Date().toISOString()});
  send(200,{message:"District updated."});return;
 }
 if(url.pathname==="/rest/v1/rpc/district_market_order"){
  let raw="";for await(const chunk of req)raw+=chunk;const {p_action:action,p_payload:p}=JSON.parse(raw);
  if(action==="create"){const total=Number(p.quantity)*Number(p.unit_price);state.player.cash-=total;districts.buy_orders.push({id:"buy-order",district_id:p.district_id,buyer_id:playerId,buyer_name:state.player.handle,good_id:p.good_id,quantity:Number(p.quantity),unit_price:Number(p.unit_price),escrow:total});}
  if(action==="cancel"){const order=districts.buy_orders.find(o=>o.id===p.order_id);state.player.cash+=order.escrow;districts.buy_orders=districts.buy_orders.filter(o=>o.id!==order.id);}
  send(200,{message:action==="create"?"Buy order funded and posted.":"Buy order cancelled. Funds returned."});return;
 }
 if(url.pathname==="/rest/v1/rpc/district_manage"){
  let raw="";for await(const chunk of req)raw+=chunk;const {p_action:action,p_payload:p}=JSON.parse(raw);
  if(action==="district"){Object.assign(districts.district,p);Object.assign(districts.districts[0],p);Object.assign(districts.management.districts[0],p);}
  send(200,{message:"Saved. The change is recorded in the audit history."});return;
 }

 if(url.pathname==="/rest/v1/rpc/market_state"){send(200,market.read(districts));return;}
 if(url.pathname==="/rest/v1/rpc/market_auction_action"){let raw="";for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw);send(200,market.action(p.p_action,p.p_payload));return;}
 if(url.pathname==="/__close_auctions"&&process.env.GAME_TEST_FIXTURE==="1"){market.expire();send(200,{ok:true});return;}
 if(url.pathname==="/__accept_telegram_invites"&&process.env.GAME_TEST_FIXTURE==="1"){telegrams.acceptInvites();send(200,{ok:true});return;}
 if(url.pathname==="/rest/v1/rpc/profile_avatar"){let raw="";for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw);state.player.avatar_url=telegrams.avatar(p.p_url);send(200,{message:"Profile picture saved.",avatar_url:state.player.avatar_url});return;}
 if(url.pathname==="/rest/v1/rpc/game_state"){send(200,{...state,server_time:new Date().toISOString()});return;}
 if(url.pathname==="/rest/v1/rpc/season_state"){send(200,{current_season_id:season.id,season,seasons:[season],boards:[{metric:"cash",label:"Cash",enabled:true,direction:"desc",include_banned:false,hall_of_fame:true,available:true,description:"Season cash."}],valuations:[],rankings:[{player_id:playerId,handle:state.player.handle,score:state.player.cash,rank:1}],total:1,offset:0,metric:"cash",my_rank:{rank:1,score:state.player.cash},hall_of_fame:[],hall_total:0,can_manage:true,can_reset:true,server_time:new Date().toISOString()});return;}
 if(url.pathname==="/__profile_setup"&&process.env.GAME_TEST_FIXTURE==="1"){let raw="";for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw);if(p.description!==undefined){state.player.description=p.description;state.player.description_version=(state.player.description_version??1)+1;}if(p.archived)state.profile_archived=true;send(200,{ok:true});return;}
 if(url.pathname==="/rest/v1/rpc/player_profile"){let raw="";for await(const chunk of req)raw+=chunk;const p=JSON.parse(raw);send(200,readProfile(state,p.p_player));return;}
 if(url.pathname==="/rest/v1/rpc/profile_description"){let raw="";for await(const chunk of req)raw+=chunk;send(200,saveDescription(state,JSON.parse(raw)));return;}
 if(url.pathname==="/rest/v1/rpc/season_profile"){send(200,{is_self:true,avatar_url:state.player.avatar_url||"/art/command-portrait.jpg",handle:state.player.handle,current_season:season.name,current:[{metric:"cash",label:"Cash",score:state.player.cash,rank:1}],previous:[],hall_of_fame:[]});return;}
 if(url.pathname==="/rest/v1/rpc/staff_state"){send(200,staff());return;}
 if(url.pathname==="/__reset_world"&&process.env.GAME_TEST_FIXTURE==="1"){resetWorld();send(200,{ok:true});return;}
 if(url.pathname==="/__visual_world"&&process.env.GAME_TEST_FIXTURE==="1"){
 resetWorld();state.player.cash=2480000;state.player.xp=1247;
 state.inventory=[{good_id:"whiskey",quantity:340},{good_id:"silk",quantity:120},{good_id:"steel",quantity:80}];
 state.businesses=state.goods.map(g=>({player_id:playerId,good_id:g.id,collected_at:new Date(Date.now()-31*60000).toISOString()}));
 districts.gang_id="gang-cobalto";districts.territory={controller_gang_id:"gang-cobalto",controller_name:"Cobalto Family",neutral_influence:6,fortification:35,status:"controlled"};
 districts.influence=[{gang_id:"gang-cobalto",name:"Cobalto Family",influence:28},{gang_id:"gang-red",name:"Red Hollow",influence:22},{gang_id:"gang-marc",name:"Marcelli Syndicate",influence:18},{gang_id:"gang-north",name:"North Docks",influence:16},{gang_id:"gang-variants",name:"The Variants",influence:10}];
 state.market=[{id:"22222222-2222-4222-8222-222222222222",seller_id:"33333333-3333-4333-8333-333333333333",seller_handle:"HarborJack",good_id:"steel",quantity:120,unit_price:180,status:"active",created_at:new Date().toISOString()}];
 send(200,{ok:true});return;
 }
 if(url.pathname==="/rest/v1/rpc/city_status"){send(200,{player_id:playerId,avatar_url:state.player.avatar_url||"/art/command-portrait.jpg",username:state.player.handle,username_claimed:true,player:{cash:state.player.cash,xp:state.player.xp,power:state.player.xp,rank:state.player.xp>=state.settings.rank_underboss?"Underboss":state.player.xp>=state.settings.rank_caporegime?"Caporegime":state.player.xp>=state.settings.rank_soldier?"Soldier":"Associate",level:1},online_count:2,window_seconds:90,poll_seconds:30,season,permissions:state.permissions,events:state.events.slice(0,8),server_time:new Date().toISOString()});return;}
 if(url.pathname==="/rest/v1/rpc/gang_directory"){send(200,{gangs:[],total:0,season,server_time:new Date().toISOString()});return;}
 if(url.pathname==="/rest/v1/rpc/social_state"){send(200,{player_id:playerId,username:state.player.handle,username_claimed:true,online_count:2,window_seconds:90,poll_seconds:3,season,permissions:state.permissions,muted:false,chat:[...community.chat].reverse(),server_time:new Date().toISOString()});return;}
 if(url.pathname==="/rest/v1/rpc/presence_leave"){send(200,null);return;}
 if(url.pathname==="/rest/v1/rpc/support_state"){send(200,{cases:community.cases,sanctions:community.sanctions});return;}
 if(url.pathname==="/rest/v1/rpc/player_directory"){
 let raw="";for await(const chunk of req)raw+=chunk;const {p_search="",p_online=false,p_offset=0}=JSON.parse(raw);
 const players=[{id:"33333333-3333-4333-8333-333333333333",username:"HarborJack",respect:800,rank:1,online:true,role:"player"},{id:playerId,username:state.player.handle,respect:state.player.xp,rank:2,online:true,role:"owner"},{id:"88888888-8888-4888-8888-888888888888",username:"IronRose",respect:0,rank:3,online:false,role:"player"}].filter(p=>p.username.toLowerCase().includes(p_search.toLowerCase())&&(!p_online||p.online));
 send(200,{players:players.slice(p_offset,p_offset+50).map(p=>({...p,avatar_url:p.id===playerId?state.player.avatar_url:"/art/command-portrait.jpg"})),total:players.length,offset:p_offset,page_size:50,my_rank:2,online_count:2,season,server_time:new Date().toISOString()});return;
 }
 if(url.pathname==="/rest/v1/rpc/community_state"){send(200,community);return;}
 if(url.pathname==="/rest/v1/rpc/staff_action"||url.pathname==="/rest/v1/rpc/community_action"){
 let raw="";for await(const chunk of req)raw+=chunk;
 const {action,payload:p}=JSON.parse(raw);
 if(action==="spawn_asset"){let row=state.inventory.find(i=>i.good_id===p.good_id);if(!row){row={good_id:p.good_id,quantity:0};state.inventory.push(row);}row.quantity+=Number(p.quantity);}
 if(action==="setting")state.settings[p.key]=Number(p.value);
 if(action==="chat")community.chat.unshift({id:String(Date.now()),player_id:playerId,handle:state.player.handle,username:state.player.handle,role:"owner",created_at:new Date().toISOString(),body:p.body});
 if(action==="ticket"||action==="report")community.cases.unshift({id:String(Date.now()),player_id:playerId,kind:action,subject:p.subject,body:p.body,status:"open",response:null,created_at:new Date().toISOString()});
 if(action==="delete_own_chat")community.chat=community.chat.filter(c=>c.id!==p.id||c.player_id!==playerId);
 if(action==="case"){const ticket=community.cases.find(c=>c.id===p.id);if(ticket){ticket.status=p.status;ticket.response=p.response;}}
 send(200,{message:"Saved."});return;
 }
 if(url.pathname==="/rest/v1/rpc/game_action"){
  let raw="";for await(const chunk of req)raw+=chunk;
  const {p_action:action,p_payload:p}=JSON.parse(raw);
  let message="Done.";
  if(action==="job"){state.player.cash+=250;state.player.xp+=10;state.player.job_ready_at=new Date(Date.now()+60000).toISOString();message="Dock errand complete. +$250 and +10 respect.";}
  if(action==="business"){const good=state.goods.find(g=>g.id===p.good_id);state.player.cash-=good.business_cost;state.businesses.push({player_id:playerId,good_id:p.good_id,collected_at:new Date().toISOString()});message="Business acquired.";}
  if(action==="buy"){const offer=state.market.find(l=>l.id===p.listing_id);state.player.cash-=offer.quantity*offer.unit_price;state.inventory.push({good_id:offer.good_id,quantity:offer.quantity});state.market=state.market.filter(l=>l.id!==offer.id);message="Deal closed. Goods delivered to your inventory.";}
  if(action==="collect"){const b=state.businesses.find(b=>b.good_id===p.good_id),good=state.goods.find(g=>g.id===p.good_id);const units=Math.min(24,Math.floor((Date.now()-Date.parse(b.collected_at))/(good.cycle_seconds*1000)))*good.batch_size;state.inventory.find(i=>i.good_id===p.good_id).quantity+=units;b.collected_at=new Date().toISOString();message="Production collected.";}
  if(action==="list"){state.inventory.find(i=>i.good_id===p.good_id).quantity-=p.quantity;const listing={id:"44444444-4444-4444-8444-444444444444",seller_id:playerId,seller_handle:state.player.handle,district_id:p.district_id,good_id:p.good_id,quantity:p.quantity,unit_price:p.unit_price,status:"active",created_at:new Date().toISOString()};state.market.push(listing);state.my_listings.push(listing);message="Offer posted.";}
  if(action==="cancel"){const listing=state.my_listings.find(l=>l.id===p.listing_id);state.inventory.find(i=>i.good_id===listing.good_id).quantity+=listing.quantity;state.market=state.market.filter(l=>l.id!==listing.id);state.my_listings=state.my_listings.filter(l=>l.id!==listing.id);message="Offer withdrawn.";}
  state.events.unshift({id:String(Date.now()),description:message,cash_delta:0,created_at:new Date().toISOString()});
  send(200,{message});return;
 }
 send(404,{error:"Not found"});
});
server.listen(54329,"127.0.0.1");
