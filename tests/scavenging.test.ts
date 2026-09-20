import test from 'node:test';
import assert from 'node:assert/strict';
import {walkingPosition,streetPoint,nearestStreetNode,type StreetSession} from '../lib/scavenging';
const session:StreetSession={district_id:'district',node:6,path:[0,5,6],departed_at:'2026-09-20T00:00:00Z',arrives_at:'2026-09-20T00:00:06Z',pending:null};
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
