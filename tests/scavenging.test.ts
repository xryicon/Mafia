import test from 'node:test';
import assert from 'node:assert/strict';
import {walkingPosition,streetPoint,type StreetSession} from '../lib/scavenging';
const session:StreetSession={district_id:'district',node:6,path:[0,5,6],departed_at:'2026-09-20T00:00:00Z',arrives_at:'2026-09-20T00:00:06Z',pending:null};
test('walking follows each street segment and clamps to server timestamps',()=>{
 const start=Date.parse(session.departed_at);
 assert.deepEqual(walkingPosition(session,start-1000),streetPoint(0));
 assert.deepEqual(walkingPosition(session,start+3000),streetPoint(5));
 assert.deepEqual(walkingPosition(session,start+4500),{x:200,y:340});
 assert.deepEqual(walkingPosition(session,start+10000),streetPoint(6));
});
test('stationary and zero-duration moves remain at their actual position',()=>{
 assert.deepEqual(walkingPosition({...session,path:[6],arrives_at:session.departed_at},Date.parse(session.departed_at)),streetPoint(6));
});
