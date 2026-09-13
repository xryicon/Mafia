export function craftingWorld(state,world,inventory){
 const recipes=[
 {id:"homemade-pistol",name:"Homemade pistol",description:"A crafted Blackwater sidearm.",blueprint_good_id:"pistol_blueprint",output_good_id:"homemade-pistol",output_units:1,seconds:150,materials:{"iron-ingot":4,"copper-ingot":2},enabled:true,version:1},
 {id:"homemade-bullets",name:"Homemade bullets",description:"Ammunition for the player economy.",blueprint_good_id:"bullet_blueprint",output_good_id:"homemade-bullets",output_units:12,seconds:60,materials:{"iron-ingot":1,"copper-ingot":1},enabled:true,version:1}];
 const learned=[],jobs=[],requests=new Map();
 const ensure=()=>{for(const [id,name,category,weight,equipment_slots] of [["homemade-pistol","Homemade pistol","weapons",2000,["secondary"]],["homemade-bullets","Homemade bullets","ammunition",30,["ammo"]],["pistol_blueprint","Homemade pistol blueprint","blueprints",50,[]],["bullet_blueprint","Homemade bullet blueprint","blueprints",50,[]],["iron-ingot","Iron ingots","materials",1000,[]],["copper-ingot","Copper ingots","materials",1000,[]]])if(!state.goods.some(g=>g.id===id))state.goods.push({id,name,business_available:false,inventory_meta:{category,weight_grams:weight,equipment_slots}});};
 const stations=()=>world.property_storage.filter(s=>s.station&&s.can_store).map(s=>{const b=world.buildings.find(b=>b.id===s.building_id),p=world.plots.find(p=>p.id===s.plot_id);return {id:s.station.id,building_id:b.id,code:p.code,name:b.building_type==="garage"?"Small garage":"Warehouse",district:world.district.name,slug:world.district.slug,ready:true,image_url:world.district.image_url};});
 const read=building=>{ensure();return {inventory:inventory.read(),server_time:new Date().toISOString(),building_id:building??null,can_manage:state.permissions.includes("roles.manage"),settings:{queue_limit:3,max_batches:20},recipes,learned,stations:stations(),jobs:jobs.filter(j=>j.status==="queued")};};
 const stock=(g,bid,source)=>{const d=inventory.read(),store=d.stores.find(s=>s.id===bid);return (source!=="storage"?state.inventory.find(i=>i.good_id===g)?.quantity??0:0)+(source!=="carried"?store?.contents.find(i=>i.good_id===g)?.quantity??0:0);};
 const consume=(g,n,bid,source)=>{const d=inventory.read(),store=d.stores.find(s=>s.id===bid);let remaining=n;if(source!=="carried"){const row=store?.contents.find(i=>i.good_id===g),take=Math.min(row?.quantity??0,n);if(row)row.quantity-=take;remaining-=take;}if(remaining)state.inventory.find(i=>i.good_id===g).quantity-=remaining;};
 const credit=(g,n,bid)=>{const rows=bid?inventory.read().stores.find(s=>s.id===bid).contents:state.inventory;let r=rows.find(i=>i.good_id===g);if(!r){r={good_id:g,quantity:0};rows.push(r);}r.quantity+=n;};
 const action=(kind,p)=>{ensure();const key=JSON.stringify({kind,p}),old=requests.get(p.request_id);if(old)return old.key===key?old.result:{error:"This crafting reference has already been used."};
 if(p.season_id!==state.season.id||state.season.status!=="open")return {error:"Crafting is paused for this season."};
 const r=recipes.find(r=>r.id===p.recipe_id),station=stations().find(s=>s.building_id===p.building_id);
 let message="";if(kind==="learn"||kind==="start"){
 if(!r?.enabled||r.version!==p.version)return {error:"The recipe changed. Review its current requirements."};
 if(kind==="learn"){if(learned.includes(r.id))return {error:"You already know this recipe."};if(stock(r.blueprint_good_id,p.building_id,p.source)<1)return {error:"Not enough materials."};consume(r.blueprint_good_id,1,p.building_id,p.source);learned.push(r.id);message="Recipe learned for this season. One blueprint was consumed.";}
 else{if(!learned.includes(r.id)||!station?.ready)return {error:"Learn the recipe and use an active station."};if(jobs.filter(j=>j.station_id===station.id&&j.status==="queued").length>=3)return {error:"This station queue is full."};if(!Number.isSafeInteger(p.batches)||p.batches<1||p.batches>20)return {error:"Choose valid batches."};
 if(Object.entries(r.materials).some(([g,n])=>stock(g,p.building_id,p.source)<n*p.batches))return {error:"Not enough materials."};
 const inputs=Object.fromEntries(Object.entries(r.materials).map(([g,n])=>[g,n*p.batches]));for(const [g,n] of Object.entries(inputs))consume(g,n,p.building_id,p.source);
 const start=Math.max(Date.now(),...jobs.filter(j=>j.station_id===station.id&&j.status==="queued").map(j=>Date.parse(j.ready_at)));
 jobs.push({id:"craft-job-"+(jobs.length+1),status:"queued",ready_at:new Date(start+r.seconds*p.batches*1000).toISOString(),starts_at:new Date(start).toISOString(),created_at:new Date().toISOString(),recipe_id:r.id,recipe_name:r.name,output_good_id:r.output_good_id,output_units:r.output_units*p.batches,inputs,station_id:station.id,building_id:station.building_id,code:station.code});
 message="Materials reserved. Crafting job added to this station.";}
 }else{const job=jobs.find(j=>j.id===p.job_id&&j.status==="queued");if(!job)return {error:"Job no longer waiting."};
 if(kind==="cancel"){for(const [g,n] of Object.entries(job.inputs))inventory.delivery(g,n,"Returned crafting materials");job.status="cancelled";message="Job cancelled. Materials are waiting in Inventory deliveries for collection.";}
 else if(kind==="collect"){if(Date.parse(job.ready_at)>Date.now())return {error:"This crafting job is still running."};const d=inventory.read(),good=d.goods.find(g=>g.id===job.output_good_id);
 if(p.destination==="storage"){const st=d.stores.find(s=>s.id===job.building_id);if(!st||st.capacity-st.used<job.output_units)return {error:"Free up storage space."};credit(good.id,job.output_units,st.id);}
 else{if(d.capacity.used_grams+good.weight_grams*job.output_units>d.capacity.weight_grams)return {error:"Free up carried slots or weight."};credit(good.id,job.output_units);}
 job.status="completed";message="Crafted items collected. Ready to store, trade or equip.";}else return {error:"Unsupported action."};}
 const result={message};requests.set(p.request_id,{key,result});return result;};
 const manage=p=>{if(!state.permissions.includes("roles.manage"))return {error:"Crafting management permission required."};const r=recipes.find(r=>r.id===p.id);if(!r||r.version!==p.version)return {error:"Recipe changed."};Object.assign(r,p,{version:r.version+1});return {message:"Recipe saved. Already queued jobs keep their original materials and output."};};
 const setup=p=>{ensure();if(p.grant)for(const [g,n] of Object.entries(p.grant))credit(g,n);if(p.ready)for(const j of jobs)j.ready_at=new Date(Date.now()-1000).toISOString();if(p.empty)state.inventory=[];};
 return {read,action,manage,setup};
}
