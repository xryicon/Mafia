import {test} from "node:test";
import assert from "node:assert/strict";
import {PerspectiveCamera,Vector3,Raycaster,Vector2,Plane,MathUtils} from "three";
import {rangeWorldPoint,rangeScorePoint,rangePlane,rangeReloadPose} from "../lib/range-3d";
test("3D target projection and shot rays preserve the server score coordinates on desktop and phones",()=>{
 for(const aspect of [.75,1.1,1.65,2.2]){const camera=new PerspectiveCamera(MathUtils.radToDeg(2*Math.atan(Math.max(4.2,4.8/aspect)/12)),aspect,.05,60);camera.position.set(0,rangePlane.centreY,0);camera.updateMatrixWorld();
 for(const [x,y] of [[0,0],[100,100],[20,45],[50,50],[80,30],[42.3,64.8]]){const w=rangeWorldPoint(x,y),projected=new Vector3(w.x,w.y,w.z).project(camera);assert.ok(Math.abs(projected.x)<=1&&Math.abs(projected.y)<=1);const ray=new Raycaster();ray.setFromCamera(new Vector2(projected.x,projected.y),camera);const hit=ray.ray.intersectPlane(new Plane(new Vector3(0,0,1),-rangePlane.z),new Vector3())!;const score=rangeScorePoint(hit.x,hit.y);assert.ok(Math.abs(score.x-x)<1e-9);assert.ok(Math.abs(score.y-y)<1e-9);}}
});
test("reload animation follows the original server deadline and settles without restarting",()=>{
 const start="2026-09-22T20:00:00Z",end="2026-09-22T20:00:02.400Z",now=Date.parse(start);assert.equal(rangeReloadPose(now+1200,start,end).progress,.5);assert.equal(rangeReloadPose(now+1200,start,end).magazine,1);assert.equal(rangeReloadPose(now+2400,start,end).active,false);assert.equal(rangeReloadPose(now+2400,start,end).tilt,0);assert.equal(rangeReloadPose(now+9999,start,end).magazine,0);assert.equal(rangeReloadPose(now,null,end).active,false);assert.equal(rangeReloadPose(now,"bad",end).active,false);
});
