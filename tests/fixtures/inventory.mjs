export function inventoryWorld(state,bin,setTool=()=>{}){
 const stores=[],entries=[],gear=[],deliveries=[],positions=new Map(),requests=new Map(),metadata={},rules=[{building_type:"warehouse",capacity:2000,enabled:true,version:1},{building_type:"garage",capacity:200,enabled:true,version:1}];
 let version=1,nextGear=1;
 const goods=()=>state.goods.map(g=>({id:g.id,name:g.name,category:g.id==="pickaxe"?"tools":g.id.endsWith("_blueprint")?"blueprints":["whiskey","silk","steel"].includes(g.id)?"commodities":"materials",description:"Goods from the Blackwater player economy.",weight_grams:g.id==="pickaxe"?2500:g.id.endsWith("_blueprint")?50:["whiskey","steel"].includes(g.id)?2000:1000,equipment_slots:g.id==="pickaxe"?["utility"]:[],...metadata[g.id]}));
 const weight=id=>goods().find(g=>g.id===id)?.weight_grams??1000;
 const load=()=>({slots:20,weight_grams:100000,used_slots:state.inventory.filter(x=>x.quantity>0).length+gear.filter(x=>x.location==="carried").length,used_grams:state.inventory.reduce((n,x)=>n+x.quantity*weight(x.good_id),0)+gear.filter(x=>x.location!=="storage").reduce((n,x)=>n+x.quantity*weight(x.good_id),0)});
 const fits=(id,n)=>{const c=load();return c.used_grams+n*weight(id)<=c.weight_grams&&(state.inventory.some(x=>x.good_id===id&&x.quantity>0)||c.used_slots<c.slots);};
 const entry=(id,delta,location,building,quantity)=>entries.unshift({id:entries.length+1,good_id:id,delta,location,building_id:building,quantity_after:quantity,reason:location==="storage"?"Secure property transfer":"Inventory "+location+" movement",created_at:new Date().toISOString()});
 const sync=()=>{const keys=[...state.inventory.filter(x=>x.quantity>0).map(x=>"good:"+x.good_id),...gear.filter(x=>x.location==="carried").map(x=>"gear:"+x.id)].sort();let changed=false;for(const [p,key] of positions)if(!keys.includes(key)){positions.delete(p);changed=true;}for(const key of keys)if(![...positions.values()].includes(key)){const p=Array.from({length:20},(_,i)=>i+1).find(p=>!positions.has(p));if(p){positions.set(p,key);changed=true;}}if(changed)version++;};
 const syncTool=()=>setTool(gear.find(g=>g.location==="equipped"&&g.equipment_slot==="utility"&&g.good_id==="pickaxe")?.condition??0);
 const read=(offset=0)=>{const b=bin(),g=gear.find(g=>g.location==="equipped"&&g.equipment_slot==="utility");
  if(g?.good_id==="pickaxe")g.condition=b.tool_condition;
  else if(!g&&b.tool_condition>0)gear.push({id:"equipped-"+nextGear++,good_id:"pickaxe",quantity:1,condition:b.tool_condition,location:"equipped",equipment_slot:"utility",building_id:null});
  sync();return {season:state.season,server_time:new Date().toISOString(),playable:state.season.status==="open",player_id:state.player.id,cash:state.player.cash,goods:goods(),carried:state.inventory.filter(i=>i.quantity>0),stores:stores.map(s=>({...s,...rules.find(r=>r.building_type===s.building_type),used:s.contents.reduce((a,x)=>a+x.quantity,0)+gear.filter(g=>g.building_id===s.id).reduce((n,g)=>n+g.quantity,0)})),committed:state.my_listings.filter(l=>l.status==="active").map(l=>({good_id:l.good_id,quantity:l.quantity,destination:"market"})),tool:{condition:b.tool_condition,maximum:b.tool_max,working:b.mining_shift},max_transfer:1000000,history:entries.slice(offset,offset+20),history_total:entries.length,offset,capacity:load(),layout:[...positions].map(([position,item_key])=>({position,item_key})),version,gear,deliveries:deliveries.filter(d=>d.quantity>0),management:state.permissions.includes("roles.manage")?{rules,building_types:[{id:"warehouse",name:"Warehouse"},{id:"garage",name:"Garage"}]}:null};};
 const fail=message=>{throw new Error(message);};
 const reorder=(key,p)=>{if(!Number.isInteger(p)||p<1||p>20)fail("Choose a valid inventory slot.");const from=[...positions].find(x=>x[1]===key)?.[0];if(!from)fail("This item is no longer carried.");const target=positions.get(p);positions.delete(from);positions.set(p,key);if(target&&from!==p)positions.set(from,target);version++;};
 const building=(id,n,storing)=>{const s=read().stores.find(s=>s.id===id);if(!s||s.foreign)fail("This is not your property.");if(s.construction_status!=="ready")fail("Storage requires your completed building.");if(s.locked)fail("District locked.");if(storing){if(!s.enabled||s.listed)fail("New storage deposits are paused.");if(s.used+n>s.capacity)fail("This building does not have enough free storage space.");}return s;};
 const action=(kind,p)=>{
  const prior=requests.get(p.request_id),key=JSON.stringify({kind,p});if(prior)return prior.key===key?prior.result:{error:"This transfer reference was already used."};
  const saved=structuredClone({inventory:state.inventory,gear,stores,entries,deliveries,positions:[...positions],version}),before=load();
  try{
   if(p.season_id!==state.season.id)fail("The season changed. Refresh your inventory.");if(state.season.status!=="open")fail("Season is closed.");sync();
   let g=gear.find(g=>"gear:"+g.id===p.item_key);
   if(kind==="move"){if(p.version!==version)fail("Inventory changed. Review the refreshed slots and try again.");reorder(p.item_key,p.position);}
   else if(kind==="equip"){
    const id=g?.good_id??p.item_key?.replace(/^good:/,""),good=goods().find(g=>g.id===id);
    if(!good?.equipment_slots.includes(p.equipment_slot))fail("This item does not fit that equipment slot.");
    if(g&&g.location!=="carried")fail("Retrieve or unequip this item first.");if(g&&g.condition===0)fail("This pickaxe is broken.");
    if(p.equipment_slot==="utility"&&bin().mining_shift)fail("Finish your mining shift before changing Utility equipment.");
    const old=gear.find(g=>g.location==="equipped"&&g.equipment_slot===p.equipment_slot);if(old){old.location="carried";old.equipment_slot=null;}
    if(!g){const row=state.inventory.find(x=>x.good_id===id);if(!row?.quantity)fail("This item is no longer carried.");row.quantity--;entry(id,-1,"carried",null,row.quantity);g={id:"equipped-"+nextGear++,good_id:id,quantity:1,condition:id==="pickaxe"?bin().tool_max:null,location:"equipped",equipment_slot:p.equipment_slot,building_id:null};gear.push(g);entry(id,1,"equipped",null,1);}
    else{g.location="equipped";g.equipment_slot=p.equipment_slot;}
    syncTool();
   }else if(["unequip","gear_store","gear_retrieve"].includes(kind)){
    if(!g)fail("This equipment is not yours.");if(g.equipment_slot==="utility"&&bin().mining_shift)fail("Finish your mining shift first.");
    if(kind==="unequip"){if(g.location!=="equipped")fail("This item is not equipped.");g.location="carried";g.equipment_slot=null;}
    else if(kind==="gear_store"){building(p.building_id,g.quantity,true);if(g.location==="storage")fail("Already stored.");g.location="storage";g.equipment_slot=null;g.building_id=p.building_id;}
    else{building(g.building_id,g.quantity,false);if(g.location!=="storage")fail("This item is not stored.");g.location="carried";g.building_id=null;}
    syncTool();sync();if(kind==="unequip"&&p.position)reorder(p.item_key,p.position);
   }else if(kind==="claim_delivery"){
    const d=deliveries.find(d=>d.id===p.delivery_id);if(!d||!Number.isSafeInteger(p.quantity)||p.quantity<1||p.quantity>d.quantity)fail("Invalid delivery quantity.");if(!fits(d.good_id,p.quantity))fail("Free a slot or reduce carried weight before collecting these goods.");
    d.quantity-=p.quantity;let row=state.inventory.find(i=>i.good_id===d.good_id);if(!row){row={good_id:d.good_id,quantity:0};state.inventory.push(row);}row.quantity+=p.quantity;
   }else{
    if(!["store","retrieve"].includes(kind))fail("Unknown inventory action.");const s=building(p.building_id,p.quantity,kind==="store");
    if(!Number.isSafeInteger(p.quantity)||p.quantity<1)fail("Enter a whole item quantity.");
    let carried=state.inventory.find(i=>i.good_id===p.good_id);if(!carried){carried={good_id:p.good_id,quantity:0};state.inventory.push(carried);}
    let item=s.contents.find(i=>i.good_id===p.good_id);if(!item){item={good_id:p.good_id,quantity:0};s.contents.push(item);}
    if(kind==="store"){if(carried.quantity<p.quantity)fail("Not enough carried stock. Refresh your inventory.");carried.quantity-=p.quantity;item.quantity+=p.quantity;}
    else{if(item.quantity<p.quantity)fail("Not enough stored stock.");if(!fits(p.good_id,p.quantity))fail("Your carried inventory is full or too heavy.");item.quantity-=p.quantity;carried.quantity+=p.quantity;}
    entry(p.good_id,kind==="store"?-p.quantity:p.quantity,"carried",null,carried.quantity);entry(p.good_id,kind==="store"?p.quantity:-p.quantity,"storage",s.id,item.quantity);
   }
   const after=load();if(after.used_grams>100000&&after.used_grams>before.used_grams||after.used_slots>20&&after.used_slots>before.used_slots)fail("Your carried inventory is full or too heavy.");sync();
   const result={message:kind==="store"?"Items secured in your property.":kind==="retrieve"?"Items returned to your carried inventory.":kind==="equip"?"Equipment updated.":kind==="move"?"Item moved.":kind==="unequip"?"Item returned with its condition preserved.":"Inventory updated."};requests.set(p.request_id,{key,result});return result;
  }catch(e){state.inventory=saved.inventory;gear.splice(0,gear.length,...saved.gear);stores.splice(0,stores.length,...saved.stores);entries.splice(0,entries.length,...saved.entries);deliveries.splice(0,deliveries.length,...saved.deliveries);positions.clear();for(const [p,k] of saved.positions)positions.set(p,k);version=saved.version;syncTool();return {error:e.message};}
 };
 const manage=(kind,p)=>{if(!state.permissions.includes("roles.manage"))return {error:"Owner inventory permission required."};if(kind==="rule"){const r=rules.find(x=>x.building_type===p.building_type);if(r.version!==Number(p.version))return {error:"These storage rules changed."};Object.assign(r,{capacity:Number(p.capacity),enabled:p.enabled==="true",version:r.version+1});}else metadata[p.good_id]={category:p.category,description:p.description,weight_grams:Number(p.weight_grams),equipment_slots:p.equipment_slots};return {message:"Inventory rules saved and recorded in the audit history."};};
 const setup=p=>{if(p.full){state.inventory=state.goods.map((g,i)=>({good_id:g.id,quantity:g.id==="pickaxe"?3:g.id.endsWith("_blueprint")?2:3+i%3}));}
  if(p.storage){stores.push({id:"cccccccc-6000-4000-8000-000000000001",plot_id:"cccccccc-6000-4000-8000-000000000011",building_type:"warehouse",name:"Warehouse",code:"W07",district:"The Waterfront",district_slug:"the-waterfront",construction_status:"ready",ready_at:new Date().toISOString(),condition:100,listed:false,locked:false,contents:[]});stores.push({...stores[0],id:"cccccccc-6000-4000-8000-000000000002",building_type:"garage",name:"Garage",code:"W08",contents:[]});}
  if(p.capacity)rules[0].capacity=p.capacity;if(p.pause)rules[0].enabled=false;if(p.foreign)stores[0].foreign=true;if(p.building)stores[0].construction_status="building";if(p.player)state.permissions=[];if(p.quantity!==undefined)state.inventory.find(i=>i.good_id==="whiskey").quantity=p.quantity;
  if(p.condition!==undefined){const g=gear.find(g=>g.equipment_slot==="utility");if(g)g.condition=p.condition;setTool(p.condition);}
  if(p.delivery)deliveries.push({id:"owed-delivery",good_id:"steel",quantity:10,reason:"Auction won",created_at:new Date().toISOString()});
  if(p.extraSlot){const id="fixture-existing-good";state.goods.push({id,name:"Fixture item",business_available:false});state.inventory.push({good_id:id,quantity:1});}
 };
 return {read,action,manage,setup};
}
