export type Recipe={id:string;name:string;input_good_id:string;output_good_id:string;fuel_good_id:string;input_units:number;output_units:number;fuel_units:number;enabled:boolean;version:number};
export type Refinery={id:string;plot_id:string;business_id:string;name:string;description:string;owner_id:string;owner_type:string;owner_name:string;district_id:string;district_name:string;district_slug:string;code:string;status:string;locked:boolean;for_sale:boolean;auction:boolean;price:number;tax_rate:number;version:number;plot_version:number;fee_mode:"cash"|"output";cash_fee:number;output_percent:number;fuel:Record<string,number>;my_cash_revenue:number;my_output_revenue:Record<string,number>};
export type RefineryReceipt={id:string;refinery_id:string;refinery_name?:string;customer_id:string;owner_id:string;input_good_id:string;input_quantity:number;output_good_id:string;output_quantity:number;fuel_good_id:string;fuel_quantity:number;cash_fee:number;owner_quantity:number;customer_quantity:number;created_at:string};
export type RefineryState={player_id:string;season:{id:string;name:string;status:string;ends_at:string|null};server_time:string;playable:boolean;can_manage:boolean;settings:Record<string,number>;cash:number;goods:{id:string;name:string}[];inventory:Record<string,number>;recipes:Recipe[];refineries:Refinery[];history:RefineryReceipt[]};
export function refiningQuote(r:Refinery,recipe:Recipe,batches:number,own:boolean){
 const output=batches*recipe.output_units,share=!own&&r.fee_mode==="output"?Math.ceil(output*Math.round(r.output_percent*100)/10000):0;
 return {input:batches*recipe.input_units,output,fuel:batches*recipe.fuel_units,share,take:output-share,cash:!own&&r.fee_mode==="cash"?r.cash_fee*batches:0};
}

// Guidance only: the server revalidates the full quote, ownership and inventory space.
export function refiningCapacity(r:Refinery,recipe:Recipe,data:RefineryState,own:boolean){
 const perBatchFee=!own&&r.fee_mode==="cash"?r.cash_fee:0;
 const max=Math.max(0,Math.floor(Math.min(data.settings.refinery_max_batches,
  recipe.input_units>0?(data.inventory[recipe.input_good_id]??0)/recipe.input_units:0,
  recipe.fuel_units>0?(r.fuel[recipe.fuel_good_id]??0)/recipe.fuel_units:Infinity,
  perBatchFee>0?data.cash/perBatchFee:Infinity)));
 return Number.isSafeInteger(max)&&max>0&&refiningQuote(r,recipe,max,own).take>0?max:0;
}
export function refiningShortages(r:Refinery,recipe:Recipe,batches:number,data:RefineryState,own:boolean){
 if(!Number.isSafeInteger(batches)||batches<1||batches>data.settings.refinery_max_batches)return [`Choose 1–${data.settings.refinery_max_batches.toLocaleString()} whole batches.`];
 const q=refiningQuote(r,recipe,batches,own),issues:string[]=[],name=(id:string)=>data.goods.find(g=>g.id===id)?.name??id;
 if(q.input>(data.inventory[recipe.input_good_id]??0))issues.push(`You need ${(q.input-(data.inventory[recipe.input_good_id]??0)).toLocaleString()} more ${name(recipe.input_good_id)}.`);
 if(q.fuel>(r.fuel[recipe.fuel_good_id]??0))issues.push(`The owner needs to load ${(q.fuel-(r.fuel[recipe.fuel_good_id]??0)).toLocaleString()} more ${name(recipe.fuel_good_id)}.`);
 if(q.cash>data.cash)issues.push(`You need $${(q.cash-data.cash).toLocaleString()} more for the service fee.`);
 if(q.take<=0)issues.push('The output fee leaves no goods for you. Increase the batch size or choose another refinery.');
 return issues;
}
