export function inventoryWorld(state,bin){
 const stores=[],entries=[],requests=new Map(),rules=[{building_type:"warehouse",capacity:2000,enabled:true,version:1},{building_type:"garage",capacity:200,enabled:true,version:1}],metadata={};
 const goods=()=>state.goods.map(g=>({id:g.id,name:g.name,category:g.id==="pickaxe"?"tools":g.id.endsWith("_blueprint")?"blueprints":["whiskey","silk","steel"].includes(g.id)?"commodities":"materials",description:"Goods from the Blackwater player economy.",...metadata[g.id]}));
 const entry=(id,delta,location,building,quantity)=>entries.unshift({id:entries.length+1,good_id:id,delta,location,building_id:building,quantity_after:quantity,reason:location==="storage"?"Secure property transfer":"Inventory movement",created_at:new Date().toISOString()});
 const read=(offset=0)=>({season:state.season,server_time:new Date().toISOString(),playable:state.season.status==="open",player_id:state.player.id,cash:state.player.cash,goods:goods(),carried:state.inventory.filter(i=>i.quantity>0),stores:stores.map(s=>({...s,...rules.find(r=>r.building_type===s.building_type),used:s.contents.reduce((a,x)=>a+x.quantity,0)})),committed:state.my_listings.filter(l=>l.status==="active").map(l=>({good_id:l.good_id,quantity:l.quantity,destination:"market"})),tool:{condition:bin().tool_condition,maximum:bin().tool_max,working:bin().mining_shift},max_transfer:1000000,history:entries.slice(offset,offset+20),history_total:entries.length,offset,management:state.permissions.includes("roles.manage")?{rules,building_types:[{id:"warehouse",name:"Warehouse"},{id:"garage",name:"Garage"}]}:null});
 const action=(kind,p)=>{
  const prior=requests.get(p.request_id),key=JSON.stringify({kind,p});if(prior)return prior.key===key?prior.result:{error:"This transfer reference was already used."};
  if(p.season_id!==state.season.id)return {error:"The season changed. Refresh your inventory."};
  if(state.season.status!=="open")return {error:"Season is closed."};
  const s=read().stores.find(s=>s.id===p.building_id);if(!s||s.foreign)return {error:"This is not your property."};
  if(s.construction_status!=="ready")return {error:"Storage requires your completed building."};
  if(!Number.isSafeInteger(p.quantity)||p.quantity<1)return {error:"Enter a whole item quantity."};
  let carried=state.inventory.find(i=>i.good_id===p.good_id);if(!carried){carried={good_id:p.good_id,quantity:0};state.inventory.push(carried);}
  let item=s.contents.find(i=>i.good_id===p.good_id);if(!item){item={good_id:p.good_id,quantity:0};s.contents.push(item);}
  if(kind==="store"){
   if(!s.enabled)return {error:"New storage deposits are paused."};if(s.used+p.quantity>s.capacity)return {error:"This building does not have enough free storage space."};
   if(carried.quantity<p.quantity)return {error:"Not enough carried stock. Refresh your inventory."};carried.quantity-=p.quantity;item.quantity+=p.quantity;
  }else{if(item.quantity<p.quantity)return {error:"Not enough stored stock."};item.quantity-=p.quantity;carried.quantity+=p.quantity;}
  entry(p.good_id,kind==="store"?-p.quantity:p.quantity,"carried",null,carried.quantity);entry(p.good_id,kind==="store"?p.quantity:-p.quantity,"storage",s.id,item.quantity);
  const result={message:kind==="store"?"Items secured in your property.":"Items returned to your carried inventory."};requests.set(p.request_id,{key,result});return result;
 };
 const manage=(kind,p)=>{if(!state.permissions.includes("roles.manage"))return {error:"Owner inventory permission required."};if(kind==="rule"){const r=rules.find(x=>x.building_type===p.building_type);if(r.version!==Number(p.version))return {error:"These storage rules changed."};Object.assign(r,{capacity:Number(p.capacity),enabled:p.enabled==="true",version:r.version+1});}else metadata[p.good_id]={category:p.category,description:p.description};return {message:"Inventory rules saved and recorded in the audit history."};};
 const setup=p=>{if(p.full){state.inventory=state.goods.map((g,i)=>({good_id:g.id,quantity:g.id==="pickaxe"?3:g.id.endsWith("_blueprint")?2:5+i*11}));}
  if(p.storage){stores.push({id:"cccccccc-6000-4000-8000-000000000001",plot_id:"cccccccc-6000-4000-8000-000000000011",building_type:"warehouse",name:"Warehouse",code:"W07",district:"The Waterfront",district_slug:"the-waterfront",construction_status:"ready",ready_at:new Date().toISOString(),condition:100,listed:false,locked:false,contents:[]});stores.push({...stores[0],id:"cccccccc-6000-4000-8000-000000000002",building_type:"garage",name:"Garage",code:"W08",contents:[]});}
  if(p.capacity)rules[0].capacity=p.capacity;if(p.pause)rules[0].enabled=false;if(p.foreign)stores[0].foreign=true;if(p.building)stores[0].construction_status="building";if(p.player)state.permissions=[];if(p.quantity!==undefined)state.inventory.find(i=>i.good_id==="whiskey").quantity=p.quantity;
 };
 return {read,action,manage,setup};
}
