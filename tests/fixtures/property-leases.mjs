// Browser fixtures; authoritative economic checks run against PostgreSQL in CI.
export function propertyWorld(world,state,inventory){
 const requests=new Map();
 const action=(action,p)=>{
  const old=requests.get(p.request_id),key=JSON.stringify({action,p});if(old)return old.key===key?old.result:{error:"Request reference already used."};
  const plot=world.plots.find(x=>x.id===p.plot_id),store=world.property_storage.find(s=>s.plot_id===p.plot_id),terms=world.lease_terms.find(t=>t.template_id===plot?.template_id),lease=world.leases.find(l=>l.plot_id===plot?.id&&l.active);
  if(!p.request_id||p.season_id!==state.season.id||!store)return {error:"Refresh your property."};
  let cost=0,message="";
  if(action==="rent"||action==="renew"){
   if(plot.owner_type!=="city"||!terms?.enabled||terms.rent!==p.rent||terms.version!==p.version)return {error:"Review the current city lease terms."};
   if(action==="rent"&&lease)return {error:"This building is already leased."};
   cost=terms.rent;if(state.player.cash<cost)return {error:"Not enough cash."};
   const ends_at=new Date(Date.now()+terms.term_hours*3600000).toISOString();
   if(action==="rent")world.leases.push({id:"lease-"+plot.id,plot_id:plot.id,building_id:store.building_id,player_id:state.player.id,player_name:state.player.handle,ends_at,active:true});else lease.ends_at=ends_at;
   store.can_access=true;store.can_store=true;inventory.cityLease(store.building_id,plot,world.buildings.find(b=>b.id===store.building_id),ends_at);
   message=action==="rent"?"The keys are yours. Your city lease is active.":"Lease extended. Rent paid in full.";
  }else if(action==="install_station"){
   if(!store.can_store||store.station||p.cost!==world.property_settings.station_cost||p.space!==world.property_settings.station_space)return {error:"Review the current installation terms."};
   cost=p.cost;if(state.player.cash<cost)return {error:"Not enough cash."};
   store.station={id:"station-"+plot.id,space:p.space,installed_at:new Date().toISOString()};inventory.station(store.building_id,p.space);message="Crafting station installed. Its floor space is reserved inside this building.";
  }else if(action==="remove_station"){store.station=null;inventory.station(store.building_id,0);message="Crafting station removed.";}
  else if(action==="vacate"){if(inventory.read().stores.find(s=>s.id===store.building_id)?.used)return {error:"Collect your stock before returning the keys."};lease.active=false;store.can_store=false;store.station=null;message="Keys returned.";}
  else return {error:"Unsupported property action."};
  state.player.cash-=cost;const result={message};requests.set(p.request_id,{key,result});return result;
 };
 const manage=(action,p)=>{
  if(action==="property"){const t=world.lease_terms.find(t=>t.template_id===p.template_id);if(t)Object.assign(t,{rent:p.rent??t.rent,term_hours:p.term_hours??t.term_hours,enabled:p.lease_enabled,version:t.version+1});for(const plot of [...world.plots,...world.management.templates])if(plot.template_id===p.template_id)Object.assign(plot,{street_id:p.street_id,image_url:p.image_url});}
  if(action==="street"){const t=world.streets.find(s=>s.id===p.id);if(t)Object.assign(t,p);else world.streets.push({...p,id:"street-new"});}
  return {message:"Property registry updated. Existing lease end dates are preserved."};
 };
 return {action,manage};
}
