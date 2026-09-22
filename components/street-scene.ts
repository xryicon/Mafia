import * as THREE from "three";
import {PointerLockControls} from "three/addons/controls/PointerLockControls.js";
import {STREET_METRES} from "@/lib/first-person-movement";
import {patrolPosition,type ScavengingState,type StreetPosition} from "@/lib/scavenging";
export type StreetInput={dx:number;dy:number;sprint:boolean};
export type StreetScene={dispose:()=>void;lock:()=>void;unlock:()=>void;touch:(x:number,y:number)=>void;look:(x:number,y:number)=>void;overview:(value:boolean)=>void;update:(state:ScavengingState,now:number)=>void};
type Options={district:string;width:number;state:ScavengingState;now:number;frame:(input:StreetInput,dt:number)=>StreetPosition;interact:()=>void;locked:(value:boolean)=>void;failed:()=>void};
// The scene is presentation only: movement inputs, proximity and all rewards are checked by the server.
export function createStreetScene(host:HTMLDivElement,options:Options):StreetScene{
 const renderer=new THREE.WebGLRenderer({antialias:true,alpha:false,powerPreference:"high-performance"});
 renderer.setPixelRatio(Math.min(window.devicePixelRatio,1.75));renderer.outputColorSpace=THREE.SRGBColorSpace;
 renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1.25;
 renderer.domElement.setAttribute('aria-label','First-person Blackwater streets');renderer.domElement.setAttribute('role','img');host.appendChild(renderer.domElement);
 const scene=new THREE.Scene();scene.background=new THREE.Color('#27343c');scene.fog=new THREE.FogExp2('#27343c',.006);
 const camera=new THREE.PerspectiveCamera(72,1,.08,320);camera.rotation.order='YXZ';camera.rotation.y=-Math.PI/2;
 const overhead=new THREE.PerspectiveCamera(48,1,1,400);overhead.position.set(84,158,145);overhead.lookAt(84,0,42);
 const controls=new PointerLockControls(camera,renderer.domElement);controls.pointerSpeed=.6;controls.minPolarAngle=.25;controls.maxPolarAngle=Math.PI-.25;
 let disposed=false,overview=false,locked=false,touchMode=false,touchX=0,touchY=0,state=options.state,time=options.now,received=performance.now(),last=performance.now(),elapsed=0;
 const keys=new Set<string>(),materials:THREE.Material[]=[],geometries:THREE.BufferGeometry[]=[],textures:THREE.Texture[]=[],patrolMeshes=new Map<string,THREE.Group>(),targets=new THREE.Group();scene.add(targets);
 const mat=(color:string,roughness=.8,metalness=0,emissive?:string)=>{const m=new THREE.MeshStandardMaterial({color,roughness,metalness,emissive:emissive??'#000000',emissiveIntensity:emissive?1.5:0});materials.push(m);return m;};
 const iron=mat('#242c30',.48,.65),stone=mat('#595954'),wood=mat('#403b31'),glass=mat('#172d35',.2,.7),gold=mat('#b89860',.5,.5),rubber=mat('#141719'),cream=mat('#b7b0a1'),lamp=mat('#ecd4a1',.5,0,'#e1a45c');
 const unitBox=new THREE.BoxGeometry(1,1,1);geometries.push(unitBox);
 function box(parent:THREE.Object3D,x:number,y:number,z:number,w:number,h:number,d:number,m:THREE.Material){const o=new THREE.Mesh(unitBox,m);o.position.set(x,y,z);o.scale.set(w,h,d);parent.add(o);return o;}
 function cylinder(parent:THREE.Object3D,x:number,y:number,z:number,r:number,h:number,m:THREE.Material,segments=10){const geo=new THREE.CylinderGeometry(r,r,h,segments);geometries.push(geo);const o=new THREE.Mesh(geo,m);o.position.set(x,y,z);parent.add(o);return o;}
 function label(text:string,x:number,y:number,z:number,width=6){const c=document.createElement('canvas');c.width=768;c.height=128;const ctx=c.getContext('2d')!;ctx.fillStyle='#111c20';ctx.fillRect(0,0,768,128);ctx.strokeStyle='#ac8959';ctx.lineWidth=5;ctx.strokeRect(5,5,758,118);ctx.fillStyle='#dfd0b4';ctx.font='36px Georgia';ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillText(text.toUpperCase(),384,64,730);const texture=new THREE.CanvasTexture(c);texture.colorSpace=THREE.SRGBColorSpace;textures.push(texture);const material=new THREE.SpriteMaterial({map:texture});materials.push(material);const o=new THREE.Sprite(material);o.position.set(x,y,z);o.scale.set(width,width/6,1);scene.add(o);return o;}
 scene.add(new THREE.HemisphereLight('#c2d4e1','#383a36',2.3));const moon=new THREE.DirectionalLight('#bdd0e2',2);moon.position.set(-40,85,30);scene.add(moon);
 const road=mat('#30373a',.55,.12),walk=mat('#6c6c64',.84),line=mat('#b2a58b');box(scene,84,-.3,42,215,.5,130,road);
 const wallTexture=new THREE.TextureLoader().load('/art/scavenging/materials/warehouse-brick.webp',()=>{if(disposed)wallTexture.dispose();});wallTexture.colorSpace=THREE.SRGBColorSpace;wallTexture.wrapS=wallTexture.wrapT=THREE.RepeatWrapping;wallTexture.repeat.set(5,3);wallTexture.anisotropy=Math.min(8,renderer.capabilities.getMaxAnisotropy());textures.push(wallTexture);
 const wall=new THREE.MeshStandardMaterial({color:'#aaa49a',map:wallTexture,roughness:.9});materials.push(wall);
 const roof=mat('#383e40',.7,.2),windowDark=mat('#22333b',.32,.5),windowLight=mat('#bca172',.6,0,'#ac7840');
 const M=STREET_METRES,r=options.width*M;
 for(let row=0;row<2;row++)for(let col=0;col<4;col++){
  const cx=(col+.5)*M,cz=(row+.5)*M,size=M-r*2,height=11+((col*7+row*3)%5)*2.4;
  box(scene,cx,0,cz,size+1.2,.35,size+1.2,walk);box(scene,cx,height/2,cz,size,height,size,wall);
  box(scene,cx,1,cz,size+.15,1.6,size+.15,stone);box(scene,cx,height,cz,size+1,.45,size+1,stone);box(scene,cx,height+.4,cz,size-1,.7,size-1,roof);
  box(scene,cx+4,height+1,cz+4,4,1.5,3,iron);cylinder(scene,cx-6,height+2.3,cz,1.5,4,iron);
  for(let face=0;face<4;face++)for(let floor=0;floor<Math.floor(height/3.5);floor++)for(let n=0;n<5;n++){
   const span=-size/2+3+n*(size-6)/4,y=3+floor*3.3,lit=(col*11+row*7+face*3+floor+n)%7<2,win=lit?windowLight:windowDark;
   if(face<2){const z=cz+(face===0?-1:1)*(size/2+.04);box(scene,cx+span,y,z,1.35,1.85,.1,iron);box(scene,cx+span,y,z+(face===0?-.06:.06),1.1,1.6,.04,win);box(scene,cx+span,y,z, .08,1.85,.22,iron);box(scene,cx+span,y,z,1.35,.08,.22,iron);}
   else{const x=cx+(face===2?-1:1)*(size/2+.04);box(scene,x,y,cz+span,.1,1.85,1.35,iron);box(scene,x+(face===2?-.06:.06),y,cz+span,.04,1.6,1.1,win);}
  }
  box(scene,cx-4,1.5,cz-size/2-.12,2,2.9,.18,wood);box(scene,cx+5,1.6,cz-size/2-.12,4,3,.2,iron);
  label(["Harbor Stores","Blackwater Freight","Foundry & Co.","Shipwright Works"][col],cx,5.6,cz-size/2-.4,8);
  // Loading docks, drains, crates and rain-darkened curb stones give the street human scale.
  for(let n=0;n<3;n++)box(scene,cx+4+n*.9,.6,cz-size/2-.6,.75,1,.75,wood);
  for(let n=0;n<4;n++)box(scene,cx-size/2-.45,.01,cz-size/2+2+n*7,.5,.04,1.4,iron);
 }
 for(let y=0;y<=2;y++)for(let x=0;x<4;x++)for(let n=0;n<6;n++)box(scene,x*M+8+n*5,.001,y*M,.9,.02,.07,line);
 for(let x=0;x<=4;x++)for(let y=0;y<2;y++)for(let n=0;n<6;n++)box(scene,x*M,.001,y*M+8+n*5,.07,.02,.9,line);
 for(let y=0;y<=2;y++)for(let x=0;x<=4;x++){
  const px=x*M+(x===4?-1:1)*(r-.45),pz=y*M+(y===2?-1:1)*(r-.45);cylinder(scene,px,2.7,pz,.08,5.4,iron);box(scene,px,5.6,pz,.52,.55,.52,lamp);box(scene,px,5.95,pz,.75,.16,.75,iron);
  if(x%2===1&&y===1){const glow=new THREE.PointLight('#efb36e',15,13,1.5);glow.position.set(px,5,pz);scene.add(glow);}
  if(x===1)label(options.state.streets[y]??options.district,px,3.7,pz,5);
 }
 // The harbour and distant skyline frame the playable streets without inventing accessible districts.
 const water=mat('#203b47',.15,.65);box(scene,84,-1.25,-34,300,.15,45,water);
 for(let i=0;i<24;i++){const h=12+(i*13%29);box(scene,-60+i*13,h/2,-90,7+(i%3)*3,h,7,iron);if(i%3===0)box(scene,-60+i*13,h+2,-90,1.2,4,1.2,stone);}
 for(let i=0;i<14;i++){const x=10+i*12;box(scene,x,-.2,-7,.25,1.4,.25,iron);box(scene,x+.5,.4,-7,12,.13,.13,iron);}
 // Batch static building detail into a few draw calls instead of one per window or brick trim.
 const batches=new Map<THREE.Material,THREE.Matrix4[]>();
 for(const child of [...scene.children])if(child instanceof THREE.Mesh&&child.geometry===unitBox&&!Array.isArray(child.material)){child.updateMatrix();const matrices=batches.get(child.material)??[];matrices.push(child.matrix.clone());batches.set(child.material,matrices);scene.remove(child);}
 for(const [material,matrices] of batches){const mesh=new THREE.InstancedMesh(unitBox,material,matrices.length);matrices.forEach((matrix,i)=>mesh.setMatrixAt(i,matrix));mesh.computeBoundingSphere();scene.add(mesh);}
 function vehicle(police=false){const g=new THREE.Group(),paint=police?iron:mat(['#30494c','#3e3232','#5a594d'][targets.children.length%3],.35,.45);box(g,0,.65,0,1.65,.6,3.7,paint);box(g,0,1.22,-.15,1.4,.8,1.8,paint);box(g,0,1.36,.78,1.21,.45,.04,glass);box(g,0,1.36,-1.08,1.21,.45,.04,glass);box(g,0,.9,1.55,1.4,.35,.65,paint);box(g,0,.45,1.95,1.85,.12,.12,cream);
  for(const x of [-.85,.85])for(const z of [-1.2,1.25]){const tyre=cylinder(g,x,.44,z,.4,.18,rubber,14);tyre.rotation.z=Math.PI/2;const hub=cylinder(g,x*1.03,.44,z,.18,.2,iron,12);hub.rotation.z=Math.PI/2;}
  for(const x of [-.55,.55])box(g,x,.79,1.93,.25,.24,.1,lamp);if(police){box(g,0,1.78,0,.6,.12,.28,cream);const beacon=cylinder(g,0,1.9,0,.13,.22,mat('#ac392a',.3,0,'#c73320'));beacon.name='beacon';}return g;}
 let targetKey='';function populate(){const key=state.targets.map(t=>t.id).join('|');if(key===targetKey)return;targetKey=key;targets.clear();for(const t of state.targets){const g=t.kind==='car'?vehicle():new THREE.Group();if(t.kind==='bin'){cylinder(g,0,.58,0,.42,1.1,iron,12);cylinder(g,0,1.16,0,.47,.09,iron,12);box(g,0,1.25,0,.19,.09,.09,gold);for(let i=0;i<8;i++){const a=i*Math.PI/4;box(g,Math.cos(a)*.4,.57,Math.sin(a)*.4,.04,.95,.04,stone);}}g.position.set((t.node%5+.035)*M,0,(Math.floor(t.node/5)+.035)*M);if(t.node%5===4)g.position.x-=.07*M;if(t.node>=10)g.position.z-=.07*M;g.userData.target=t.id;targets.add(g);}}
 populate();const playerMarker=cylinder(scene,0,1,0,.9,1,mat('#b8cca5',.5,0,'#638976'));playerMarker.visible=false;
 const exit=label('District exit',0,3.8,0,5);
 const onLock=()=>{locked=true;touchMode=false;options.locked(true);},onUnlock=()=>{locked=false;keys.clear();options.locked(touchMode);};controls.addEventListener('lock',onLock);controls.addEventListener('unlock',onUnlock);
 const keydown=(e:KeyboardEvent)=>{if(!locked)return;if(['KeyW','KeyA','KeyS','KeyD','ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Space','ShiftLeft','ShiftRight'].includes(e.code)){e.preventDefault();keys.add(e.code);}if(e.code==='KeyE'&&!e.repeat)options.interact();};const keyup=(e:KeyboardEvent)=>keys.delete(e.code),blur=()=>{keys.clear();touchX=touchY=0;controls.unlock();},visibility=()=>{if(document.hidden)blur();};
 window.addEventListener('keydown',keydown);window.addEventListener('keyup',keyup);window.addEventListener('blur',blur);document.addEventListener('visibilitychange',visibility);
 const resize=()=>{const w=host.clientWidth,h=host.clientHeight;renderer.setSize(w,h);camera.aspect=w/Math.max(1,h);camera.updateProjectionMatrix();overhead.aspect=camera.aspect;overhead.updateProjectionMatrix();};const observer=new ResizeObserver(resize);observer.observe(host);resize();
 const reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
 const lost=(e:Event)=>{e.preventDefault();options.failed();};renderer.domElement.addEventListener('webglcontextlost',lost);
 function tick(){if(disposed)return;const stamp=performance.now(),dt=Math.min(.08,(stamp-last)/1000);last=stamp;elapsed+=dt;const now=time+stamp-received;
  let side=0,forward=0;if(!document.hidden&&!overview&&(locked||touchMode)){side=touchX+(keys.has('KeyD')||keys.has('ArrowRight')?1:0)-(keys.has('KeyA')||keys.has('ArrowLeft')?1:0);forward=-touchY+(keys.has('KeyW')||keys.has('ArrowUp')?1:0)-(keys.has('KeyS')||keys.has('ArrowDown')?1:0);}
  const yaw=camera.rotation.y,input={dx:Math.cos(yaw)*side-Math.sin(yaw)*forward,dy:-Math.sin(yaw)*side-Math.cos(yaw)*forward,sprint:keys.has('ShiftLeft')||keys.has('ShiftRight')};const mag=Math.max(1,Math.hypot(input.dx,input.dy));input.dx/=mag;input.dy/=mag;
  const p=options.frame(input,dt),driving=!!state.operations?.pursuit?.vehicle_id;camera.position.set(p[0]*M,(driving?1.25:1.72)+(!reduced&&Math.hypot(input.dx,input.dy)>.1?Math.sin(elapsed*9)*.025:0),p[1]*M);playerMarker.position.set(p[0]*M,1,p[1]*M);playerMarker.visible=overview;exit.visible=!!state.operations?.pursuit;
  const patrols=state.operations?.pursuit?.patrols??state.patrols??[];for(const [id,g] of patrolMeshes)if(!patrols.some(p=>p.id===id)){scene.remove(g);patrolMeshes.delete(id);}for(const patrol of patrols){let g=patrolMeshes.get(patrol.id);if(!g){g=vehicle(true);patrolMeshes.set(patrol.id,g);scene.add(g);}const a=patrolPosition(patrol,now),b=patrolPosition(patrol,now+150);g.position.set(a[0]*M,0,a[1]*M);if(Math.hypot(b[0]-a[0],b[1]-a[1])>.001)g.rotation.y=Math.atan2(b[0]-a[0],b[1]-a[1]);g.getObjectByName('beacon')!.visible=Math.sin(elapsed*10)>-.2;}
  if(!document.hidden)renderer.render(scene,overview?overhead:camera);
 }
 renderer.setAnimationLoop(tick);
 return {lock:()=>{if(matchMedia('(pointer: coarse)').matches){touchMode=true;options.locked(true);}else{const request=controls.lock();void request;}},unlock:()=>{touchMode=false;controls.unlock();options.locked(false);},touch:(x,y)=>{touchX=x;touchY=y;touchMode=true;},look:(x,y)=>{touchMode=true;camera.rotation.y-=x*.004;camera.rotation.x=Math.max(-1.25,Math.min(1.25,camera.rotation.x-y*.004));},overview:(v)=>{overview=v;if(v)controls.unlock();},update:(s,n)=>{state=s;time=n;received=performance.now();populate();},dispose:()=>{disposed=true;renderer.setAnimationLoop(null);controls.unlock();controls.dispose();observer.disconnect();window.removeEventListener('keydown',keydown);window.removeEventListener('keyup',keyup);window.removeEventListener('blur',blur);document.removeEventListener('visibilitychange',visibility);renderer.domElement.removeEventListener('webglcontextlost',lost);geometries.forEach(g=>g.dispose());materials.forEach(m=>m.dispose());textures.forEach(t=>t.dispose());renderer.dispose();renderer.domElement.remove();}};
}
