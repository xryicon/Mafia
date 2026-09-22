import test from "node:test";
import assert from "node:assert/strict";
import {acknowledgedStreetPosition,applyStreetCorrection,beginStreetCorrection,meaningfulDirectionChange,predictStreetPosition,predictionDeadline,predictionDeadlineForInput,predictionSeconds,streetSendInterval} from "../lib/street-prediction";
import {onStreet,streetSight} from "../lib/first-person-movement";
import type {StreetSession} from "../lib/scavenging";

const session=(from:[number,number],to:[number,number],start=1_000,end=1_500):StreetSession=>({district_id:"district",node:0,path:[0],route_points:[from,to],departed_at:new Date(start).toISOString(),arrives_at:new Date(end).toISOString(),pending:null});
const moving={dx:1,dy:0,sprint:false},still={dx:0,dy:0,sprint:false};

test("delayed acknowledgments replay the accepted route before reconciliation",()=>{
 const s=session([0,0],[.05,0]);
 assert.ok(Math.abs(acknowledgedStreetPosition(s,1_100,200)[0]-.02)<1e-9);
 assert.equal(predictionDeadline(5_000,s,1_100,200),5_300);
});

test("send cadence reserves rate-limit headroom for Owner settings",()=>{
 assert.equal(streetSendInterval(360),175);
 assert.equal(streetSendInterval(60),1_050);
 assert.ok(60_000/streetSendInterval(1_200)<1_200);
});

test("an idle restart gets one bounded lease and a stop never extrapolates",()=>{
 const deadline=10_500;
 assert.equal(predictionDeadlineForInput(0,10_000,500,still,moving),deadline);
 assert.equal(predictionDeadlineForInput(deadline,10_100,500,moving,still),0);
 assert.equal(predictionSeconds(10_000,10_016,deadline),.016);
 assert.ok(predictStreetPosition([0,0],moving,10_000,10_016,deadline,10,.13)[0]>0);
 assert.deepEqual(predictStreetPosition([0,0],still,10_000,10_400,deadline,10,.13),[0,0]);
 assert.equal(meaningfulDirectionChange(still,moving),true);
 assert.equal(meaningfulDirectionChange(still,{...still,sprint:true}),false);
 assert.equal(meaningfulDirectionChange(moving,{dx:.96,dy:.04,sprint:false}),false);
});

test("long gaps and repeated frames cannot extrapolate past the lease",()=>{
 const point=predictStreetPosition([0,0],moving,20_000,30_000,20_500,10,.13);
 assert.ok(Math.abs(point[0]-.05)<1e-9);
 let after=point;for(let frame=0;frame<100;frame++)after=predictStreetPosition(after,moving,30_000+frame*16,30_016+frame*16,20_500,10,.13);
 assert.deepEqual(after,point);
});

test("reconciliation stays on streets and never smooths through a building",()=>{
 const width=.13,unsafe=beginStreetCorrection([.129,.135],[.135,.129],width);
 assert.deepEqual(unsafe,{point:[.135,.129],remaining:[0,0]});
 const correction=beginStreetCorrection([0,0],[.08,0],width),next=applyStreetCorrection(correction.point,correction.remaining,.016,width);
 assert.ok(onStreet(next.point,width));assert.ok(streetSight(correction.point,next.point,width));assert.ok(next.point[0]>0&&next.point[0]<.08);
 const blocked=applyStreetCorrection([.129,.135],[.006,-.006],.125,width);
 assert.deepEqual(blocked,{point:[.129,.135],remaining:[0,0]});
});
