import * as THREE from "three";
import {RoundedBoxGeometry} from "three/addons/geometries/RoundedBoxGeometry.js";
import {rangeTarget,rangeImpact,type RangeConfig,type RangeSession,type RangeMagazine} from "@/lib/range";
import {rangePlane,rangeWorldPoint,rangeScorePoint,rangeReloadPose} from "@/lib/range-3d";
export type RangeFrame={session:RangeSession|null;config:RangeConfig;weapon:string|null;magazine:RangeMagazine|undefined;now:number;aim:{x:number;y:number};reducedMotion:boolean};
export type RangeScene={render:(state:RangeFrame)=>void;aim:(x:number,y:number)=>{x:number;y:number}|null;dispose:()=>void};
export function createRangeScene(host:HTMLDivElement,onLost:()=>void):RangeScene{
 const renderer=new THREE.WebGLRenderer({antialias:true,alpha:false,powerPreference:"low-power"});renderer.setPixelRatio(Math.min(window.devicePixelRatio,1.5));renderer.outputColorSpace=THREE.SRGBColorSpace;renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1.2;renderer.autoClear=false;
 const canvas=renderer.domElement;canvas.setAttribute("aria-label","Indoor shooting range with firing booths and moving paper targets");canvas.setAttribute("role","img");host.append(canvas);
 const scene=new THREE.Scene();scene.background=new THREE.Color("#252c29");scene.fog=new THREE.Fog("#252c29",14,36);const camera=new THREE.PerspectiveCamera(38,1,.05,60);camera.position.set(0,rangePlane.centreY,0);camera.lookAt(0,rangePlane.centreY,-12);
 const hands=new THREE.Scene(),handCamera=new THREE.PerspectiveCamera(58,1,.01,10);const geometries:THREE.BufferGeometry[]=[],materials:THREE.Material[]=[],textures:THREE.Texture[]=[];
 const geo=<T extends THREE.BufferGeometry>(g:T)=>{geometries.push(g);return g;};
 const mat=(color:string,metalness=0,roughness=.8)=>{const m=new THREE.MeshStandardMaterial({color,metalness,roughness});materials.push(m);return m;};
 const concrete=mat("#454e4b"),dark=mat("#222b29",.3),metal=mat("#54645d",.7,.4),brass=mat("#b19350",.7,.35),wood=mat("#73563a"),rubber=mat("#242624");
 const box=(parent:THREE.Object3D,w:number,h:number,d:number,x:number,y:number,z:number,m:THREE.Material)=>{const mesh=new THREE.Mesh(geo(parent===scene?new THREE.BoxGeometry(w,h,d):new RoundedBoxGeometry(w,h,d,2,Math.min(w,h,d)*.16)),m);mesh.position.set(x,y,z);parent.add(mesh);return mesh;};
 const cylinder=(parent:THREE.Object3D,r:number,len:number,x:number,y:number,z:number,m:THREE.Material)=>{const o=new THREE.Mesh(geo(new THREE.CylinderGeometry(r,r,len,12)),m);o.rotation.x=Math.PI/2;o.position.set(x,y,z);parent.add(o);return o;};
 function label(text:string,w:number,h:number,color="#dbc391",background="#15221e"){
  const c=document.createElement("canvas");c.width=512;c.height=128;const ctx=c.getContext("2d")!;ctx.fillStyle=background;ctx.fillRect(0,0,512,128);ctx.strokeStyle=color;ctx.lineWidth=5;ctx.strokeRect(8,8,496,112);ctx.fillStyle=color;ctx.font="bold 44px Georgia";ctx.textAlign="center";ctx.textBaseline="middle";ctx.fillText(text,256,64,472);const texture=new THREE.CanvasTexture(c);texture.colorSpace=THREE.SRGBColorSpace;textures.push(texture);const m=new THREE.MeshBasicMaterial({map:texture});materials.push(m);return new THREE.Mesh(geo(new THREE.PlaneGeometry(w,h)),m);
 }
 // Subtle concrete grain and expansion joints keep the hall readable without image downloads.
 const floorCanvas=document.createElement("canvas");floorCanvas.width=256;floorCanvas.height=256;const fc=floorCanvas.getContext("2d")!,pixels=fc.createImageData(256,256);let noise=71;for(let i=0;i<pixels.data.length;i+=4){noise=(Math.imul(noise,1664525)+1013904223)>>>0;const v=150+(noise%28);pixels.data[i]=v;pixels.data[i+1]=v;pixels.data[i+2]=v;pixels.data[i+3]=255;}fc.putImageData(pixels,0,0);fc.strokeStyle="#797f7a";fc.lineWidth=1;fc.strokeRect(.5,.5,255,255);const floorTexture=new THREE.CanvasTexture(floorCanvas);floorTexture.colorSpace=THREE.SRGBColorSpace;floorTexture.wrapS=floorTexture.wrapT=THREE.RepeatWrapping;floorTexture.repeat.set(7,12);textures.push(floorTexture);concrete.map=floorTexture;
 scene.add(new THREE.HemisphereLight("#e9e7dc","#384240",2.3));const light=new THREE.DirectionalLight("#eef1e5",3.2);light.position.set(2,5,1);scene.add(light);hands.add(new THREE.HemisphereLight("#fff0d3","#455150",3));const handLight=new THREE.DirectionalLight("#fff0d0",4);handLight.position.set(-1,2,1);hands.add(handLight);
 box(scene,14,.25,24,0,-.15,-10,concrete);box(scene,14,.2,24,0,4.4,-10,dark);box(scene,.3,4.6,24,-7,2.2,-10,concrete);box(scene,.3,4.6,24,7,2.2,-10,concrete);box(scene,14,4.5,.6,0,2,-20,rubber);
 for(let i=0;i<18;i++)box(scene,13,.11,.17,0,.15+i*.23,-19.55,dark);
 for(let x=-6;x<=6;x+=3){box(scene,.035,.015,19,x,.005,-10,brass);box(scene,.06,.09,15,x,3.3,-9,metal);if(x!==0){box(scene,.12,.25,2.7,x,2,-1.4,metal);box(scene,.09,2.4,2.6,x,1.2,-1.4,dark);}}
 // The player's booth and adjacent booths stay on the safe side of the firing line.
 for(const x of [-1.2,1.2]){box(scene,.1,2.6,3.6,x,1.3,-.8,dark);box(scene,.14,.07,3.6,x,2.63,-.8,brass);box(scene,.15,.95,.15,x,.48,-2.4,metal);}
 box(scene,2.4,.1,.65,0,.9,-1.7,wood);box(scene,14,.015,.09,0,.005,-2.3,brass);
 for(let z=-3;z>=-18;z-=4){box(scene,13,.2,.3,0,4.05,z,metal);const glow=new THREE.MeshBasicMaterial({color:"#fff0c3"});materials.push(glow);for(const x of [-4,0,4])box(scene,1.65,.025,.18,x,3.93,z,glow);}
 for(const x of [-5.7,5.7]){const n=label(x<0?"LANE 01":"LANE 03",1.4,.35);n.position.set(x,2.8,-8);scene.add(n);}
 const sign=label("BLACKWATER · TRAINING HALL",5,.65);sign.position.set(0,3.55,-19.1);scene.add(sign);
 const targetGroups:THREE.Group[]=[],paperMaterials:THREE.MeshBasicMaterial[]=[],paperTextures:THREE.CanvasTexture[]=[],paperCanvases:HTMLCanvasElement[]=[];
 let lastSession:string|null=null,lastRound=-1,lastShot:string|null=null,weaponId:string|null=null,shotAt=-Infinity,lastConfig="";
 const holes:{lane:number;x:number;y:number}[]=[];let weapon=new THREE.Group(),magazine=new THREE.Group(),support=new THREE.Group(),slide=new THREE.Group(),muzzle=new THREE.Group();hands.add(weapon);
 function buildWeapon(id:string|null){
  // Reuse tracked resources until disposal; loadout changes are infrequent.
  hands.remove(weapon);weapon=new THREE.Group();hands.add(weapon);magazine=new THREE.Group();support=new THREE.Group();slide=new THREE.Group();muzzle=new THREE.Group();weapon.add(magazine,support,slide,muzzle);weapon.visible=!!id;if(!id)return;
  const rifle=id==="m4-carbine",steel=mat("#68716e",.65,.35),polymer=mat("#39403b",.15,.6),glove=mat("#5d6151"),sleeve=mat("#273b32");
  if(rifle){
   box(weapon,.12,.14,.4,0,0,-.1,steel);box(weapon,.09,.075,.42,0,.065,-.39,polymer);cylinder(weapon,.026,.52,0,.06,-.74,steel);cylinder(weapon,.036,.09,0,.06,-1.04,polymer);
   box(weapon,.1,.055,.3,0,.025,.25,steel);box(weapon,.13,.22,.21,0,-.04,.44,polymer);const grip=box(weapon,.085,.21,.1,0,-.16,.055,polymer);grip.rotation.x=-.25;
   box(magazine,.075,.26,.14,0,-.2,-.12,steel);for(let i=0;i<4;i++)box(magazine,.078,.014,.145,0,-.12-i*.04,-.12,polymer);
   box(weapon,.08,.055,.7,0,.135,-.26,steel);for(let i=0;i<16;i++)box(weapon,.095,.02,.018,0,.17,.03-i*.043,polymer);
   for(const x of [-.051,.051])for(let i=0;i<6;i++)box(weapon,.008,.025,.035,x,.055,-.3-i*.047,steel);
   const sight=new THREE.Mesh(geo(new THREE.TorusGeometry(.037,.009,8,20)),polymer);sight.position.set(0,.225,-.08);weapon.add(sight);box(weapon,.02,.09,.025,0,.18,-.75,steel);box(weapon,.08,.012,.02,0,.225,-.75,steel);
   box(slide,.045,.035,.12,.063,.025,-.025,brass);box(weapon,.075,.12,.05,.035,-.04,.045,polymer);
   box(support,.115,.1,.18,-.07,-.07,-.42,glove);const arm=box(support,.14,.15,.54,-.11,-.16,-.22,sleeve);arm.rotation.x=-.33;
   muzzle.position.set(0,.06,-1.1);
  }else{
   box(slide,.11,.115,.36,0,.065,-.13,steel);box(weapon,.1,.065,.29,0,-.02,-.085,polymer);const grip=box(weapon,.105,.25,.12,0,-.14,.055,wood);grip.rotation.x=-.22;
   cylinder(weapon,.027,.055,0,.057,-.335,steel);box(magazine,.085,.16,.09,0,-.2,.04,steel);box(weapon,.023,.03,.032,0,.137,-.26,polymer);box(weapon,.08,.035,.025,0,.137,.017,polymer);
   for(const x of [-.057,.057])for(let i=0;i<5;i++)box(slide,.007,.07,.008,x,.06,-.02-i*.013,polymer);
   box(support,.13,.13,.19,-.055,-.16,.04,glove);const arm=box(support,.15,.17,.55,-.13,-.25,.22,sleeve);arm.rotation.x=-.25;muzzle.position.set(0,.06,-.38);
  }
  box(weapon,.12,.13,.16,.045,-.13,.065,glove);const arm=box(weapon,.16,.17,.6,.11,-.25,.35,sleeve);arm.rotation.x=-.24;
  const flashMat=new THREE.MeshBasicMaterial({color:"#ffe6a6",transparent:true,opacity:.9,depthWrite:false});materials.push(flashMat);const flash=new THREE.Mesh(geo(new THREE.ConeGeometry(.075,.22,7)),flashMat);flash.rotation.x=-Math.PI/2;flash.position.z=-.06;muzzle.add(flash);muzzle.visible=false;
 }
 function paper(lane:number,c:RangeConfig){const ctx=paperCanvases[lane].getContext("2d")!,w=512,h=768,cx=256,cy=h*1.65/3.1,rx=w/2.7,ry=h/3.1;
  ctx.fillStyle="#cbbb98";ctx.fillRect(0,0,w,h);ctx.strokeStyle="#8c7959";ctx.lineWidth=4;ctx.strokeRect(10,10,w-20,h-20);ctx.fillStyle="#29302c";ctx.beginPath();ctx.ellipse(cx,cy-ry*.85,rx*.35,ry*.38,0,0,Math.PI*2);ctx.fill();ctx.fillRect(cx-rx*.72,cy-ry*.55,rx*1.44,ry*1.55);
  for(const k of [1,.7,c.bullseye_percent/100]){ctx.strokeStyle=k===c.bullseye_percent/100?"#bf7d4f":"#b9a67b";ctx.lineWidth=3;ctx.beginPath();ctx.ellipse(cx,cy,rx*k,ry*k,0,0,Math.PI*2);ctx.stroke();}ctx.fillStyle="#bd7545";ctx.beginPath();ctx.arc(cx,cy,5,0,Math.PI*2);ctx.fill();ctx.fillStyle="#55462f";ctx.textAlign="center";ctx.font="bold 22px Georgia";ctx.fillText("BLACKWATER  /  "+(lane+1),cx,h-30);
  for(const hole of holes.filter(h=>h.lane===lane)){const x=cx+hole.x/(c.radius_x*27)*w,y=cy+hole.y/(c.radius_y*18.6)*h;ctx.fillStyle="#e4d4ac";ctx.beginPath();for(let j=0;j<12;j++){const r=j%2?6:11,a=j*Math.PI/6;ctx.lineTo(x+Math.cos(a)*r,y+Math.sin(a)*r);}ctx.closePath();ctx.fill();ctx.fillStyle="#151a17";ctx.beginPath();ctx.arc(x,y,5,0,Math.PI*2);ctx.fill();}paperTextures[lane].needsUpdate=true;
 }
 function rebuildTargets(c:RangeConfig){for(const group of targetGroups)scene.remove(group);targetGroups.length=0;paperCanvases.length=0;paperMaterials.length=0;paperTextures.length=0;
  for(let i=0;i<c.targets_per_round;i++){const group=new THREE.Group(),cv=document.createElement("canvas");cv.width=512;cv.height=768;paperCanvases.push(cv);const texture=new THREE.CanvasTexture(cv);texture.colorSpace=THREE.SRGBColorSpace;texture.anisotropy=Math.min(4,renderer.capabilities.getMaxAnisotropy());textures.push(texture);paperTextures.push(texture);const material=new THREE.MeshBasicMaterial({map:texture,side:THREE.DoubleSide});materials.push(material);paperMaterials.push(material);const width=c.radius_x/100*rangePlane.width*2.7,height=c.radius_y/100*rangePlane.height*3.1;const target=new THREE.Mesh(geo(new THREE.PlaneGeometry(width,height)),material);target.position.y=-(height/2-c.radius_y/100*rangePlane.height*1.65);group.add(target);box(group,.11,.05,.07,0,height*.53,0,metal);box(group,.015,2,.015,0,height*.53+1,0,metal);targetGroups.push(group);scene.add(group);paper(i,c);}
 }
 const handRay=new THREE.Raycaster(),weaponDirection=new THREE.Vector3(),forward=new THREE.Vector3(0,0,-1);
 const ray=new THREE.Raycaster(),plane=new THREE.Plane(new THREE.Vector3(0,0,1),-rangePlane.z),intersection=new THREE.Vector3();
 const resize=()=>{const w=Math.max(1,host.clientWidth),h=Math.max(1,host.clientHeight);renderer.setSize(w,h,false);camera.aspect=w/h;camera.fov=THREE.MathUtils.radToDeg(2*Math.atan(Math.max(4.2,4.8/camera.aspect)/12));camera.updateProjectionMatrix();camera.updateMatrixWorld();handCamera.aspect=w/h;handCamera.updateProjectionMatrix();};const observer=new ResizeObserver(resize);observer.observe(host);resize();
 const contextLost=(e:Event)=>{e.preventDefault();onLost();};canvas.addEventListener("webglcontextlost",contextLost);
 return{aim(x,y){ray.setFromCamera(new THREE.Vector2(x*2-1,1-y*2),camera);if(!ray.ray.intersectPlane(plane,intersection))return null;const p=rangeScorePoint(intersection.x,intersection.y);return{x:Math.max(0,Math.min(100,p.x)),y:Math.max(0,Math.min(100,p.y))};},render(f){
  const s=f.session,c=f.config,elapsed=s?Math.max(0,Math.floor(f.now-Date.parse(s.started_at))):0,active=s?.status==="active"&&f.now<Date.parse(s.ends_at),round=Math.min(c.rounds-1,Math.floor(elapsed/(c.round_seconds*1000)));
  if(f.weapon!==weaponId){weaponId=f.weapon;buildWeapon(weaponId);}
  if((s?.id??null)!==lastSession||round!==lastRound){holes.length=0;lastSession=s?.id??null;lastRound=round;lastShot=s?.last_shot?.id??null;shotAt=-Infinity;const retained=s?.last_shot&&s.last_shot.round===round?rangeImpact(s.seed,s.last_shot,c):null;if(retained)holes.push(retained);for(let i=0;i<paperCanvases.length;i++)paper(i,c);}
  const configKey=[c.radius_x,c.radius_y,c.targets_per_round,c.bullseye_percent].join(":");if(configKey!==lastConfig){lastConfig=configKey;rebuildTargets(c);}
  const shot=s?.last_shot;if(shot&&shot.id!==lastShot){lastShot=shot.id;shotAt=performance.now();const impact=rangeImpact(s.seed,shot,c);if(impact&&impact.round===round){holes.push(impact);paper(impact.lane,c);}}
  for(let lane=0;lane<targetGroups.length;lane++){const p=rangeTarget(s?.seed??100,round,lane,active?elapsed:0,c),w=rangeWorldPoint(p.x,p.y);targetGroups[lane].position.set(w.x,w.y,w.z);paperMaterials[lane].color.set(s?.hit_targets.includes(`${round}:${lane}`)?"#cfc7b4":"#ffffff");}
  const recoil=Math.max(0,1-(performance.now()-shotAt)/180),reload=rangeReloadPose(f.now,f.magazine?.started_at,f.magazine?.ready_at),rifle=f.weapon==="m4-carbine";
  const lean=f.reducedMotion?0:reload.tilt;weapon.position.set((rifle ? .25 : .18)-lean*.12,-.27+lean*.1,-.65-lean*.32+recoil*(f.reducedMotion ? .012 : .045));handRay.setFromCamera(new THREE.Vector2((f.aim.x*2-1)*(1-lean),(1-f.aim.y*2)*(1-lean)),handCamera);weaponDirection.copy(handRay.ray.direction).multiplyScalar(30).sub(weapon.position).normalize();weapon.quaternion.setFromUnitVectors(forward,weaponDirection);weapon.rotateX(recoil*(f.reducedMotion?0:.065)+lean*.28);weapon.rotateZ(-lean*.55);
  if(handCamera.aspect<1)weapon.position.x*=.65;magazine.position.y=f.reducedMotion?0:-reload.magazine*.16;magazine.rotation.x=f.reducedMotion?0:reload.magazine*.2;const reach=f.reducedMotion?0:reload.hand;support.position.set(-reach*.08,-reach*.09,reach*.1);slide.position.z=recoil*.025;muzzle.visible=recoil>.65&&!reload.active&&!f.reducedMotion;
  canvas.dataset.weapon=f.weapon??"none";canvas.dataset.reloading=String(reload.active);canvas.dataset.shot=lastShot??"";
  renderer.clear();renderer.render(scene,camera);renderer.clearDepth();renderer.render(hands,handCamera);
 },dispose(){observer.disconnect();canvas.removeEventListener("webglcontextlost",contextLost);for(const g of geometries)g.dispose();for(const m of materials)m.dispose();for(const t of textures)t.dispose();renderer.dispose();renderer.forceContextLoss();canvas.remove();}};
}
