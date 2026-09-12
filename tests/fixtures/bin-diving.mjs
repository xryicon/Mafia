// Isolated CI fixture. Ownership, rolls and accounting are verified in real PostgreSQL.
export function binWorld(game,mining){
 let rules={enabled:true,cooldown_seconds:120,cash_min:25,cash_max:150,cash_chance:35,pickaxe_chance:8,pistol_blueprint_chance:3,bullet_blueprint_chance:4,version:1};
 let inventory={},history=[],nonce=new Map(),next="pickaxe",admin=true,ready=null;
 const catalog=structuredClone(mining.catalog);
 function read(){return {season:game.season,server_time:new Date().toISOString(),playable:game.season.status==="open",can_manage:admin,rules,districts:catalog,cash:game.player.cash,inventory,tool_condition:mining.read().tool.durability,tool_max:100,mining_shift:!!mining.read().shift,ready_at:ready,history};}
 function action(action,p){
  if(nonce.has(p.request_id))return nonce.get(p.request_id);
  if(action==="configure"){if(!admin)return {error:"Owner permission required."};if(p.version!==rules.version)return {error:"Another edit was saved. Refresh."};rules={...rules,...p,version:rules.version+1};const r={message:"Bin diving rules saved."};nonce.set(p.request_id,r);return r;}
  if(action==="equip"){if(!inventory.pickaxe)return {error:"Find a pickaxe first."};inventory.pickaxe--;mining.equip();const r={message:"Pickaxe equipped. Visit a public mine to put it to work."};nonce.set(p.request_id,r);return r;}
  const d=catalog.find(d=>d.id===p.district_id);
  if(!d||d.status==="lockdown"||!rules.enabled||ready&&Date.parse(ready)>Date.now())return {error:"This dive is unavailable."};
  const receipt={id:"dive-"+history.length,district_id:d.id,district_name:d.name,outcome:next,cash:next==="cash"?75:0,created_at:new Date().toISOString(),ready_at:new Date(Date.now()+rules.cooldown_seconds*1000).toISOString()};
  if(next==="cash")game.player.cash+=75;else if(next!=="nothing")inventory[next]=(inventory[next]??0)+1;
  ready=receipt.ready_at;history.unshift(receipt);const r={message:next==="nothing"?"Nothing useful this time.":"You found something worth keeping.",receipt};nonce.set(p.request_id,r);return r;
 }
 return {read,action,setup:p=>{if(p.next)next=p.next;if(p.ready)ready=null;if(p.player)admin=false;if(p.lockdown)catalog[0].status="lockdown";if(p.addDistrict)catalog.push({...catalog[0],id:"new-district",slug:"new-district",name:"New District",status:"neutral"});}};
}
