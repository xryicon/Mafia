// Isolated browser-test service. Never imported by the application.
import http from "node:http";
import { playerId, token, user } from "./identity.mjs";
const season={id:"55555555-5555-4555-8555-555555555555",name:"Founding Season",status:"open",starting_cash:10000,starting_crates:5,starts_at:null,ends_at:null,locked_at:null,opened_at:new Date().toISOString(),archived_at:null,reset_at:null,hall_of_fame_places:3};
const state = {season,
 jobs:[{"id":"docks","name":"Dock errand","district":"THE DOCKS","description":"Build connections.","reward":250,"xp":10,"cooldown":60},{"id":"warehouse","name":"Warehouse shift","district":"INDUSTRIAL QUARTER","description":"Keep goods moving.","reward":600,"xp":20,"cooldown":180},{"id":"courier","name":"Night courier","district":"OLD TOWN","description":"Work the night shift.","reward":1100,"xp":40,"cooldown":360}],
 settings:{market_fee_percent:5,listing_limit:20,max_listing_quantity:1000,max_unit_price:1000000,offline_batches:24,rank_soldier:250,rank_caporegime:800,rank_underboss:2000},
 permissions:['economy.manage','roles.manage'],ledger:[],
 player:{id:playerId,handle:"Rookie-11111111",cash:10000,xp:0,job_ready_at:"2026-09-10T00:00:00Z",created_at:user.created_at},
 goods:[
  {id:"whiskey",name:"Whiskey crates",business_name:"Backroom distillery",business_cost:3000,batch_size:3,cycle_seconds:300},
  {id:"silk",name:"Silk bolts",business_name:"Textile workshop",business_cost:5000,batch_size:2,cycle_seconds:300},
  {id:"steel",name:"Steel bundles",business_name:"Dockside foundry",business_cost:8000,batch_size:2,cycle_seconds:300}],
 inventory:[{good_id:"whiskey",quantity:5}],businesses:[],
 market:[{id:"22222222-2222-4222-8222-222222222222",seller_id:"33333333-3333-4333-8333-333333333333",seller_handle:"Harbor-Jack",good_id:"silk",quantity:2,unit_price:100,status:"active",created_at:user.created_at}],
 my_listings:[],events:[{id:"welcome",description:"Arrived in Blackwater",cash_delta:10000,created_at:user.created_at}],
 server_time:new Date().toISOString(),
};
const community={chat:[],cases:[],sanctions:[]};
const staff=()=>({permissions:state.permissions,players:[{id:playerId,handle:state.player.handle,role_id:"owner"}],sanctions:[],cases:community.cases,evidence:[],chat:community.chat,
 settings:[{key:"market_fee_percent",value:state.settings.market_fee_percent,minimum:0,maximum:100}],jobs:[],goods:state.goods,
 moderator_permissions:["players.warn"],permission_catalog:[{id:"players.warn",owner_only:false}],audit:[]});
const server = http.createServer(async(req,res) => {
 res.setHeader("Access-Control-Allow-Origin","http://localhost:3000");
 res.setHeader("Access-Control-Allow-Headers",req.headers["access-control-request-headers"] || "*");
 res.setHeader("Access-Control-Allow-Methods","GET, POST, OPTIONS");
 res.setHeader("Content-Type","application/json");
 if(req.method==="OPTIONS"){res.writeHead(204);res.end();return;}
 const url=new URL(req.url,"http://127.0.0.1:54329");
 const send=(status,data)=>{res.writeHead(status);res.end(JSON.stringify(data));};
 if(url.pathname==="/health"){send(200,{ok:true});return;}
 if(url.pathname==="/auth/v1/token"){send(400,{error:"invalid_grant",error_description:"Invalid test code"});return;}
 if(req.headers.authorization!=="Bearer "+token){send(401,{code:"bad_jwt",message:"Invalid session"});return;}
 if(url.pathname==="/auth/v1/user"){send(200,user);return;}
 if(url.pathname==="/rest/v1/rpc/game_state"){send(200,{...state,server_time:new Date().toISOString()});return;}
 if(url.pathname==="/rest/v1/rpc/season_state"){send(200,{current_season_id:season.id,season,seasons:[season],boards:[{metric:"cash",label:"Cash",enabled:true,direction:"desc",include_banned:false,hall_of_fame:true,available:true,description:"Season cash."}],valuations:[],rankings:[{player_id:playerId,handle:state.player.handle,score:state.player.cash,rank:1}],total:1,offset:0,metric:"cash",my_rank:{rank:1,score:state.player.cash},hall_of_fame:[],hall_total:0,can_manage:true,can_reset:true,server_time:new Date().toISOString()});return;}
 if(url.pathname==="/rest/v1/rpc/season_profile"){send(200,{handle:state.player.handle,current_season:season.name,current:[{metric:"cash",label:"Cash",score:state.player.cash,rank:1}],previous:[],hall_of_fame:[]});return;}
 if(url.pathname==="/rest/v1/rpc/staff_state"){send(200,staff());return;}
 if(url.pathname==="/rest/v1/rpc/community_state"){send(200,community);return;}
 if(url.pathname==="/rest/v1/rpc/staff_action"||url.pathname==="/rest/v1/rpc/community_action"){
 let raw="";for await(const chunk of req)raw+=chunk;
 const {action,payload:p}=JSON.parse(raw);
 if(action==="setting")state.settings[p.key]=Number(p.value);
 if(action==="chat")community.chat.unshift({id:String(Date.now()),player_id:playerId,handle:state.player.handle,body:p.body});
 if(action==="ticket"||action==="report")community.cases.unshift({id:String(Date.now()),player_id:playerId,kind:action,subject:p.subject,body:p.body,status:"open"});
 send(200,{message:"Saved."});return;
 }
 if(url.pathname==="/rest/v1/rpc/game_action"){
  let raw="";for await(const chunk of req)raw+=chunk;
  const {p_action:action,p_payload:p}=JSON.parse(raw);
  let message="Done.";
  if(action==="job"){state.player.cash+=250;state.player.xp+=10;state.player.job_ready_at=new Date(Date.now()+60000).toISOString();message="Dock errand complete. +$250 and +10 respect.";}
  if(action==="business"){const good=state.goods.find(g=>g.id===p.good_id);state.player.cash-=good.business_cost;state.businesses.push({player_id:playerId,good_id:p.good_id,collected_at:new Date().toISOString()});message="Business acquired.";}
  if(action==="buy"){const offer=state.market.find(l=>l.id===p.listing_id);state.player.cash-=offer.quantity*offer.unit_price;state.inventory.push({good_id:offer.good_id,quantity:offer.quantity});state.market=state.market.filter(l=>l.id!==offer.id);message="Deal closed. Goods delivered to your inventory.";}
  if(action==="list"){state.inventory.find(i=>i.good_id===p.good_id).quantity-=p.quantity;const listing={id:"44444444-4444-4444-8444-444444444444",seller_id:playerId,seller_handle:state.player.handle,good_id:p.good_id,quantity:p.quantity,unit_price:p.unit_price,status:"active",created_at:new Date().toISOString()};state.market.push(listing);state.my_listings.push(listing);message="Offer posted.";}
  if(action==="cancel"){const listing=state.my_listings.find(l=>l.id===p.listing_id);state.inventory.find(i=>i.good_id===listing.good_id).quantity+=listing.quantity;state.market=state.market.filter(l=>l.id!==listing.id);state.my_listings=state.my_listings.filter(l=>l.id!==listing.id);message="Offer withdrawn.";}
  state.events.unshift({id:String(Date.now()),description:message,cash_delta:0,created_at:new Date().toISOString()});
  send(200,{message});return;
 }
 send(404,{error:"Not found"});
});
server.listen(54329,"127.0.0.1");
