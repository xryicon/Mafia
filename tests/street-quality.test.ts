import test from 'node:test';
import assert from 'node:assert/strict';
import {streetPixelRatio,adaptStreetResolution} from '../lib/street-quality';
test('street rendering bounds GPU pixel load on desktop, phones and high-DPI screens',()=>{
 for(const [w,h,dpr] of [[1440,900,1],[390,650,3],[3840,2160,2]]){
  const ratio=streetPixelRatio(w,h,dpr,'auto',w<700);assert.ok(w*h*ratio*ratio<=1400001);assert.ok(ratio<=dpr);assert.ok(Number.isFinite(ratio));
 }
 assert.ok(streetPixelRatio(1440,900,2,'performance',false)<streetPixelRatio(1440,900,2,'high',false));
});
test('adaptive resolution ignores short samples and recovers gradually within safe bounds',()=>{
 assert.equal(adaptStreetResolution(1,80,4),1);assert.equal(adaptStreetResolution(1,32,90),.9);assert.equal(adaptStreetResolution(1,100,30),.9);assert.equal(adaptStreetResolution(1,500,6),.9);assert.equal(adaptStreetResolution(.6,40,90),.6);assert.equal(adaptStreetResolution(.7,16,180),.75);assert.equal(adaptStreetResolution(1,16,180),1);
});
