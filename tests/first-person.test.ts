import test from 'node:test';
import assert from 'node:assert/strict';
import {footStep,onStreet,streetSight} from '../lib/first-person-movement';
test('walking stays inside the district and slides along buildings without crossing corners',()=>{
 for(let x=0;x<=4;x+=.08)for(let y=0;y<=2;y+=.08){const p:[number,number]=[x,y];if(!onStreet(p))continue;for(const [dx,dy] of [[1,1],[-1,1],[1,-1],[-1,-1]]){const next=footStep(p,dx,dy,.8,4);assert.ok(onStreet(next));assert.ok(streetSight(p,next));assert.ok(Math.hypot(next[0]-x,next[1]-y)<=.200001);}}
});
test('diagonal movement does not make a player faster and building blocks obscure sight',()=>{
 const a=footStep([0,0],1,0,.5,10),b=footStep([0,0],1,1,.5,10);assert.ok(Math.abs(Math.hypot(...a)-Math.hypot(...b))<1e-9);
 assert.equal(streetSight([.129,.135],[.135,.129]),false);assert.equal(streetSight([0,0],[4,0]),true);assert.equal(streetSight([0,.5],[1,.5]),false);
 assert.deepEqual(footStep([0,0],-1,-1,10,10),[0,0]);assert.deepEqual(footStep([0,0],0,0,.5,10),[0,0]);
});
