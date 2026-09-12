import {playerId} from "./identity.mjs";
export function readProfile(state,id){
 const self=id===playerId;if(![playerId,"33333333-3333-4333-8333-333333333333","88888888-8888-4888-8888-888888888888"].includes(id))return null;
 const respect=self?state.player.xp:800,name=self?state.player.handle:"HarborJack";
 return {player_id:id,handle:name,is_self:self,avatar_url:self?state.player.avatar_url||"/art/command-portrait.jpg":"/art/command-portrait.jpg",description:self?state.player.description??"":"Trade fairly. Remember your friends. The waterfront rewards patience.",
 description_version:self?state.player.description_version??1:null,description_limit:300,joined_at:state.player.created_at,online:true,role:self?"owner":"player",respect,level:1,title:respect>=2000?"Underboss":respect>=800?"Caporegime":respect>=250?"Soldier":"Associate",respect_rank:self?2:1,gang:self?null:{id:"fixture-gang",name:"The Waterfront Family"},season:state.season,
 current:[{metric:"respect",label:"Respect",score:respect,rank:self?2:1},{metric:"net_worth",label:"Net worth",score:14500,rank:2}],
 previous:state.profile_archived?[{season_id:"99999999-9999-4999-8999-999999999999",season_name:"The First Light",metric:"respect",label:"Respect",score:3200,rank:4}]:[],
 businesses:(self?state.businesses:[{good_id:"whiskey"},{good_id:"steel"}]).map(b=>({id:b.good_id,name:state.goods.find(g=>g.id===b.good_id)?.business_name??"Dockside business",kind:"production",status:"open",district:null,plot_code:null,href:"/market?good="+b.good_id,image_url:"/art/harbor.webp"})),business_total:self?state.businesses.length:2,plot_count:self?0:2,districts:self?[]:[{id:"waterfront",name:"The Waterfront",slug:"the-waterfront"}],server_time:new Date().toISOString()};
}
export function saveDescription(state,p){
 const version=state.player.description_version??1;
 if(p.p_version!==version)return {error:"Your description changed in another tab. Reopen the editor and try again.",conflict:true};
 if(typeof p.p_description!=="string"||p.p_description.trim().length>300)return {error:"Your description is too long."};
 state.player.description=p.p_description.trim();state.player.description_version=version+1;
 return {description:state.player.description,description_version:version+1,message:"Profile description saved."};
}
