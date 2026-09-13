import {strict as assert} from "node:assert";
import {test} from "node:test";
import {rangeTarget,rangeImpact,formatRangeAccuracy,type RangeShot,type RangeConfig} from "../lib/range";
import {isProtectedPage} from "../lib/auth-paths";
const c={targets_per_round:3,round_seconds:5,move_speed:300,move_amplitude:12,move_vertical:15,radius_x:7,radius_y:12} as RangeConfig;
test("moving target hit areas stay inside the lane at allowed extremes",()=>{
 for(const count of [1,2,3])for(let t=0;t<5000;t+=83)for(let l=0;l<count;l++){const p=rangeTarget(999999,29,l,t,{...c,targets_per_round:count});assert.ok(p.x-p.rx>0&&p.x+p.rx<100&&p.y-p.ry>0&&p.y+p.ry<100);}
});
test("range geometry remains deterministic across refresh and timestamps",()=>{
 assert.deepEqual(rangeTarget(37,0,1,1250,c),rangeTarget(37,0,1,1250,c));assert.notDeepEqual(rangeTarget(37,0,1,1250,c),rangeTarget(37,0,1,1500,c));
 const p=rangeTarget(37,0,0,1250,{...c,move_amplitude:0,move_vertical:0});assert.equal(p.x,20);assert.equal(p.y,45);assert.equal(formatRangeAccuracy(null),"—");assert.equal(formatRangeAccuracy(0),"0");assert.equal(formatRangeAccuracy(100),"100");assert.equal(formatRangeAccuracy(33.333),"33.3");assert.ok(isProtectedPage("/shooting-range"));
});

test("paper holes use shot-time geometry, including repeated hits and non-scoring paper edges",()=>{
 const seed=37,elapsed=1250,p=rangeTarget(seed,0,1,elapsed,c);
 const shot={id:"verified-shot",hit:true,points:100,round:0,lane:1,x:p.x+2,y:p.y-1,elapsed_ms:elapsed,created_at:"2026-09-13T20:00:00Z"} as RangeShot;
 const hole=rangeImpact(seed,shot,c)!;
 assert.equal(hole.lane,1);assert.ok(Math.abs(hole.x-20)<.000001);assert.ok(Math.abs(hole.y+6)<.000001);
 assert.deepEqual(rangeImpact(seed,{...shot,hit:false,points:0,lane:null},c),hole);
 const edge=rangeImpact(seed,{...shot,hit:false,points:0,lane:null,x:p.x+c.radius_x*1.2,y:p.y},c)!;
 assert.equal(edge.lane,1);
 assert.equal(rangeImpact(seed,{...shot,lane:null,x:0,y:0},c),null);
 assert.equal(rangeImpact(seed,{...shot,elapsed_ms:NaN},c),null);
 // Network reply timing cannot move a hole: only the stored elapsed time positions it.
 assert.deepEqual(rangeImpact(seed,{...shot,created_at:"2026-09-13T20:00:02Z"},c),hole);
});
