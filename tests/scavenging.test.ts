import test from 'node:test';
import assert from 'node:assert/strict';
import {walkingPosition,streetPoint,nearestStreetNode,nearestStreetPosition,mapPoint,routePosition,type StreetSession} from '../lib/scavenging';
const session:StreetSession={district_id:'district',node:6,path:[0,5,6],departed_at:'2026-09-20T00:00:00Z',arrives_at:'2026-09-20T00:00:06Z',pending:null};
test('free clicks stop between crossings and project onto a road, never inside buildings',()=>{
 assert.deepEqual(nearestStreetPosition(181,114),[.5,0]);
 for(let x=-100;x<=1100;x+=37)for(let y=-100;y<=800;y+=31){const p=nearestStreetPosition(x,y);assert.ok(p[0]>=0&&p[0]<=4&&p[1]>=0&&p[1]<=2);assert.ok(Number.isInteger(p[0])||Number.isInteger(p[1]));}
 assert.deepEqual(mapPoint([.5,0]),{x:181,y:114});
});
test('continuous routes interpolate by distance, preserve turns, and handle duplicate endpoints',()=>{
 const route:[number,number][]=[[.25,0],[1,0],[1,0],[1,1.5]];
 assert.deepEqual(routePosition(route,0),[.25,0]);assert.deepEqual(routePosition(route,1/3),[1,0]);assert.deepEqual(routePosition(route,1),[1,1.5]);
 assert.deepEqual(walkingPosition({...session,route_points:route},Date.parse(session.arrives_at)),mapPoint([1,1.5]));
});
test('walking follows each street segment and clamps to server timestamps',()=>{
 const start=Date.parse(session.departed_at);
 assert.deepEqual(walkingPosition(session,start-1000),streetPoint(0));
 assert.deepEqual(walkingPosition(session,start+3000),streetPoint(5));
 assert.deepEqual(walkingPosition(session,start+4500),{x:181,y:344});
 assert.deepEqual(walkingPosition(session,start+10000),streetPoint(6));
});
test('stationary and zero-duration moves remain at their actual position',()=>{
 assert.deepEqual(walkingPosition({...session,path:[6],arrives_at:session.departed_at},Date.parse(session.departed_at)),streetPoint(6));
});
test('map clicks resolve to the visible street crossings and stay within the map',()=>{
 for(let node=0;node<15;node++){const point=streetPoint(node);assert.equal(nearestStreetNode(point.x+5,point.y-5),node);}
 assert.equal(nearestStreetNode(-200,-200),0);
 assert.equal(nearestStreetNode(2000,2000),14);
});
