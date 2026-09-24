import test from 'node:test';
import assert from 'node:assert/strict';
import {refiningCapacity,refiningShortages,refiningQuote,type Refinery,type Recipe,type RefineryState} from '../lib/refineries';
const recipe:Recipe={id:'iron',name:'Iron refining',input_good_id:'iron-ore',output_good_id:'iron-ingot',fuel_good_id:'coal',input_units:20,output_units:10,fuel_units:5,enabled:true,version:1};
const refinery={fee_mode:'cash',cash_fee:20,output_percent:15,fuel:{coal:30}} as Refinery;
const state={cash:100,inventory:{'iron-ore':200},settings:{refinery_max_batches:100},goods:[{id:'iron-ore',name:'Iron ore'},{id:'coal',name:'Coal'}]} as unknown as RefineryState;
test('maximum respects the tightest ore, fuel, cash and configured batch limit',()=>{
 assert.equal(refiningCapacity(refinery,recipe,state,false),5);
 assert.equal(refiningCapacity(refinery,recipe,state,true),6);
 assert.equal(refiningCapacity(refinery,recipe,{...state,inventory:{'iron-ore':39}},true),1);
 assert.equal(refiningCapacity(refinery,recipe,{...state,settings:{refinery_max_batches:2}},true),2);
 assert.equal(refiningCapacity({...refinery,fuel:{}},recipe,state,false),0);
 assert.equal(refiningCapacity({...refinery,cash_fee:0},recipe,{...state,cash:0},false),6);
});
test('output share uses existing round-up rules and ignores customer cash',()=>{
 const output={...refinery,fee_mode:'output' as const};
 assert.equal(refiningCapacity(output,recipe,{...state,cash:0},false),6);
 assert.deepEqual(refiningQuote(output,recipe,1,false),{input:20,output:10,fuel:5,share:2,take:8,cash:0});
 assert.equal(refiningCapacity({...output,output_percent:100},recipe,state,false),0);
});
test('shortages identify exact missing resources and reject invalid quantities',()=>{
 assert.deepEqual(refiningShortages(refinery,recipe,11,state,false),['You need 20 more Iron ore.','The owner needs to load 25 more Coal.','You need $120 more for the service fee.']);
 for(const batches of [0,-1,1.5,NaN,Infinity,101])assert.match(refiningShortages(refinery,recipe,batches,state,false)[0],/whole batches/);
 assert.deepEqual(refiningShortages(refinery,recipe,5,state,false),[]);
});
