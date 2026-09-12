// Isolated browser fixture; real transaction authority is tested in PostgreSQL.
export function refineryWorld(game,playerId){
 const other="33333333-3333-4333-8333-333333333333",newGoods=[["iron-ore","Iron ore"],["copper-ore","Copper ore"],["coal","Coal"],["iron-ingot","Iron ingots"],["copper-ingot","Copper ingots"]];
 let admin=true,r={id:"refinery-1",plot_id:"rf-plot",business_id:"rf-business",name:"Copper Quay Refinery",description:"A coal-fired player refinery.",owner_id:"city",owner_type:"city",owner_name:"Blackwater Refining Authority",district_id:"waterfront",district_name:"The Waterfront",district_slug:"the-waterfront",code:"RF-01",status:"open",locked:false,for_sale:true,auction:false,price:3500,tax_rate:3,version:1,plot_version:1,fee_mode:"cash",cash_fee:20,output_percent:10,fuel:{coal:0},my_cash_revenue:0,my_output_revenue:{}};
 const recipes=[{id:"iron",name:"Iron refining",input_good_id:"iron-ore",output_good_id:"iron-ingot",fuel_good_id:"coal",input_units:20,output_units:10,fuel_units:5,enabled:true,version:1},{id:"copper",name:"Copper refining",input_good_id:"copper-ore",output_good_id:"copper-ingot",fuel_good_id:"coal",input_units:20,output_units:10,fuel_units:5,enabled:true,version:1}];
 let inventory={"coal":100,"iron-ore":200,"copper-ore":200},history=[],requests=new Map();
 function read(){return {player_id:playerId,season:game.season,server_time:new Date().toISOString(),playable:game.season.status==="open",can_manage:admin,settings:{refinery_max_cash_fee:10000,refinery_max_output_percent:50,refinery_max_batches:100,refinery_fuel_capacity:10000},cash:game.player.cash,inventory,goods:[...game.goods.filter(x=>!newGoods.some(([id])=>id===x.id)),...newGoods.map(([id,name])=>({id,name}))],recipes,refineries:[r],history};}
 function action(action,p){
  if(requests.has(p.request_id))return requests.get(p.request_id);
  let result={message:"Refinery updated."};
  if(action==="buy"){if(!r.for_sale)return {error:"No longer for sale."};game.player.cash-=3605;Object.assign(r,{owner_type:"player",owner_id:playerId,owner_name:game.player.handle,for_sale:false,plot_version:2});result.message="Refinery acquired.";}
  if(action==="settings"){if(r.owner_id!==playerId)return {error:"Only the refinery owner can change fees."};Object.assign(r,{fee_mode:p.fee_mode,cash_fee:p.cash_fee,output_percent:p.output_percent,status:p.status,version:r.version+1});result.message="Refinery fees and opening status saved.";}
  if(action==="stock"){if(inventory[p.good_id]<p.quantity)return {error:"Not enough fuel."};inventory[p.good_id]-=p.quantity;r.fuel[p.good_id]=(r.fuel[p.good_id]??0)+p.quantity;result.message="Fuel moved.";}
  if(action==="withdraw"){if((r.fuel[p.good_id]??0)<p.quantity)return {error:"Not enough fuel."};r.fuel[p.good_id]-=p.quantity;inventory[p.good_id]=(inventory[p.good_id]??0)+p.quantity;result.message="Fuel moved.";}
  if(action==="refine"){
   const recipe=recipes.find(x=>x.id===p.recipe_id),own=r.owner_id===playerId;
   if(p.version!==r.version||p.plot_version!==r.plot_version||p.recipe_version!==recipe.version)return {error:"Ownership or fees changed. Refresh and review the quote."};
   const input=recipe.input_units*p.batches,output=recipe.output_units*p.batches,fuel=recipe.fuel_units*p.batches,share=!own&&r.fee_mode==="output"?Math.ceil(output*r.output_percent/100):0,fee=!own&&r.fee_mode==="cash"?r.cash_fee*p.batches:0;
   if(r.status!=="open"||inventory[recipe.input_good_id]<input||(r.fuel[recipe.fuel_good_id]??0)<fuel)return {error:"The refinery cannot fill this order."};
   inventory[recipe.input_good_id]-=input;r.fuel[recipe.fuel_good_id]-=fuel;inventory[recipe.output_good_id]=(inventory[recipe.output_good_id]??0)+output-share;game.player.cash-=fee;
   const receipt={id:"receipt-"+history.length,refinery_id:r.id,refinery_name:r.name,customer_id:playerId,owner_id:r.owner_id,input_good_id:recipe.input_good_id,input_quantity:input,output_good_id:recipe.output_good_id,output_quantity:output,fuel_good_id:recipe.fuel_good_id,fuel_quantity:fuel,cash_fee:fee,owner_quantity:share,customer_quantity:output-share,created_at:new Date().toISOString()};
   history.unshift(receipt);result={message:"Ore refined. Your output is in your inventory.",receipt};
  }
  if(action==="recipe"){if(!admin)return {error:"Owner permission required."};const recipe=recipes.find(x=>x.id===p.id);Object.assign(recipe,p,{version:recipe.version+1});result.message="Refining recipe saved.";}
  requests.set(p.request_id,result);return result;
 }
 return {read,action,setup:p=>{if(p.customer)Object.assign(r,{owner_id:other,owner_type:"player",owner_name:"Harbor Jack",for_sale:false,fuel:{coal:100}});if(p.mode)r.fee_mode=p.mode;if(p.empty)r.fuel.coal=0;if(p.player)admin=false;if(p.reprice){r.cash_fee=500;r.version++;}}};
}
