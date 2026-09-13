import {strict as assert} from "node:assert";
import {test} from "node:test";
import {rangeTarget,accuracy,type RangeConfig} from "../lib/range";
import {isProtectedPage} from "../lib/auth-paths";
const c={targets_per_round:3,round_seconds:5,move_speed:300,move_amplitude:12,move_vertical:15,radius_x:7,radius_y:12} as RangeConfig;
test("moving target hit areas stay inside the lane at allowed extremes",()=>{
 for(const count of [1,2,3])for(let t=0;t<5000;t+=83)for(let l=0;l<count;l++){const p=rangeTarget(999999,29,l,t,{...c,targets_per_round:count});assert.ok(p.x-p.rx>0&&p.x+p.rx<100&&p.y-p.ry>0&&p.y+p.ry<100);}
});
test("range geometry remains deterministic across refresh and timestamps",()=>{
 assert.deepEqual(rangeTarget(37,0,1,1250,c),rangeTarget(37,0,1,1250,c));assert.notDeepEqual(rangeTarget(37,0,1,1250,c),rangeTarget(37,0,1,1500,c));
 const p=rangeTarget(37,0,0,1250,{...c,move_amplitude:0,move_vertical:0});assert.equal(p.x,20);assert.equal(p.y,45);assert.equal(accuracy(0,0),0);assert.equal(accuracy(1,3),33);assert.ok(isProtectedPage("/shooting-range"));
});
