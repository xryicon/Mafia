import * as THREE from "three";
import {STREET_METRES} from "@/lib/first-person-movement";
type Context={scene:THREE.Scene;width:number;streets:string[];district:string;materials:THREE.Material[];textures:THREE.Texture[];geometries:THREE.BufferGeometry[];box:(parent:THREE.Object3D,x:number,y:number,z:number,w:number,h:number,d:number,m:THREE.Material)=>THREE.Mesh;cylinder:(parent:THREE.Object3D,x:number,y:number,z:number,r:number,h:number,m:THREE.Material,segments?:number)=>THREE.Mesh;mat:(color:string,roughness?:number,metalness?:number,emissive?:string)=>THREE.MeshStandardMaterial;anisotropy:number};
// Decorative geometry never changes the district collision grid or creates gameplay properties.
export function createStreetEnvironment(c:Context){
 const {scene,box,cylinder,mat,materials,textures,geometries}=c,M=STREET_METRES,r=c.width*M;
 let disposed=false,loaded=0;const loader=new THREE.TextureLoader();
 const texture=(url:string,repeatX=1,repeatY=1)=>{const t=loader.load(url,()=>{loaded++;for(const other of textures)if(other.source===t.source)other.needsUpdate=true;if(disposed)t.dispose();});t.colorSpace=THREE.SRGBColorSpace;t.wrapS=t.wrapT=THREE.RepeatWrapping;t.repeat.set(repeatX,repeatY);t.anisotropy=c.anisotropy;textures.push(t);return t;};
 const sky=texture('/art/scavenging/materials/blackwater-harbor-panorama.webp');sky.mapping=THREE.EquirectangularReflectionMapping;scene.background=sky;scene.environment=sky;scene.environmentIntensity=.28;scene.backgroundIntensity=.75;
 scene.fog=new THREE.FogExp2('#263039',.0038);
 scene.add(new THREE.HemisphereLight('#a9bccd','#302820',1.6));const moon=new THREE.DirectionalLight('#b8c5dd',1.25);moon.position.set(-35,75,-30);scene.add(moon);
 const asphalt=texture('/art/scavenging/materials/dockside-asphalt.webp',32,20),bricks=texture('/art/scavenging/materials/warehouse-brick.webp',3,2);
 const road=mat('#9ca4a7',.62,.12);road.map=asphalt;const bump=asphalt.clone();bump.colorSpace=THREE.NoColorSpace;textures.push(bump);road.bumpMap=bump;road.bumpScale=.035;box(scene,84,-.32,42,186,.55,103,road);
 const stone=mat('#626467',.9),trim=mat('#343b3e',.75,.2),iron=mat('#243138',.5,.55),wood=mat('#69513b'),roof=mat('#343c40',.8,.15),paint=mat('#aaa48e'),glass=mat('#243b48',.22,.45),lit=mat('#8d7451',.5,.1,'#b07835');lit.emissiveIntensity=.5;
 const walls=['#9b8878','#787d7b','#8e7565'].map(color=>{const m=mat(color,.88);m.map=bricks;return m;});
 const floorGeo=new THREE.PlaneGeometry(1,1);geometries.push(floorGeo);
 const plane=(x:number,y:number,z:number,w:number,h:number,m:THREE.Material)=>{const p=new THREE.Mesh(floorGeo,m);p.position.set(x,y,z);p.scale.set(w,h,1);scene.add(p);return p;};
 const sign=(text:string,x:number,y:number,z:number,w:number,h:number,side=Math.PI)=>{
  const canvas=document.createElement('canvas');canvas.width=768;canvas.height=192;const ctx=canvas.getContext('2d')!;ctx.fillStyle='#162024';ctx.fillRect(0,0,768,192);ctx.strokeStyle='#796143';ctx.lineWidth=8;ctx.strokeRect(12,12,744,168);ctx.fillStyle='#d1bc92';ctx.font='bold 44px Georgia';ctx.textAlign='center';ctx.textBaseline='middle';ctx.fillText(text.toUpperCase(),384,92,705);ctx.font='16px sans-serif';ctx.fillStyle='#938571';ctx.fillText('BLACKWATER · EST. 1892',384,150);const t=new THREE.CanvasTexture(canvas);t.colorSpace=THREE.SRGBColorSpace;textures.push(t);const m=new THREE.MeshStandardMaterial({map:t,roughness:.8});materials.push(m);const p=plane(x,y,z,w,h,m);p.rotation.y=side;return p;
 };
 // Each collision block contains adjoining façades with different roof lines and ground-floor uses.
 for(let row=0;row<2;row++)for(let col=0;col<4;col++){
  const cx=(col+.5)*M,cz=(row+.5)*M,size=M-2*r-2,front=cz-size/2;
  box(scene,cx,-.02,cz,size+1.1,.25,size+1.1,stone);
  for(let wing=0;wing<2;wing++){
   const w=size/2,x=cx-size/2+w*(wing+.5),height=9+((col*5+row*3+wing*2)%5)*2.1;
   box(scene,x,height/2,cz,w,height,size,walls[(row+col+wing)%walls.length]);
   box(scene,x,.72,cz,w+.1,1.4,size+.1,stone);box(scene,x,height-.15,cz,w+.24,.4,size+.24,trim);box(scene,x,height+.3,cz,w+.5,.36,size+.5,stone);
   for(let floor=0;floor<Math.floor(height/3.3);floor++)for(let n=0;n<3;n++)for(const back of [false,true]){
    const px=x-w/2+2+n*(w-4)/2,y=2.8+floor*3.1,z=back?cz+size/2+.055:front-.055,wm=(row*7+col*11+wing+floor+n)%5===0?lit:glass;
    box(scene,px,y,z,1.45,1.9,.2,trim);box(scene,px,y,z+(back?.12:-.12),1.17,1.62,.05,wm);box(scene,px,y-.95,z,1.75,.13,.5,stone);box(scene,px,y,z, .075,1.8,.35,iron);box(scene,px,y,z,1.35,.07,.35,iron);
   }
   if((row+col+wing)%2===0){
    // Pitched roof uses a single low-poly prism, not extra intersecting building volumes.
    const vertices=new Float32Array([-w/2,0,-size/2,w/2,0,-size/2,0,2.8,-size/2,-w/2,0,size/2,w/2,0,size/2,0,2.8,size/2]);const geo=new THREE.BufferGeometry();geo.setAttribute('position',new THREE.BufferAttribute(vertices,3));geo.setIndex([0,2,1,3,4,5,0,3,5,0,5,2,2,5,4,2,4,1]);geo.computeVertexNormals();geometries.push(geo);const mesh=new THREE.Mesh(geo,roof);mesh.position.set(x,height+.4,cz);scene.add(mesh);
   }else{box(scene,x,height+.55,cz,w-.6,.5,size-.6,roof);box(scene,x+w/2-1,height+1,cz, .3,1.3,size,trim);}
   box(scene,x+2,height+1.3,cz+5,1.2,2.6,1.2,walls[0]);box(scene,x+2,height+2.65,cz+5,1.55,.2,1.55,stone);
   const doorX=x-2.5;box(scene,doorX,1.4,front-.13,1.85,2.8,.22,trim);box(scene,doorX,1.36,front-.27,1.55,2.55,.12,wood);box(scene,doorX+.5,1.2,front-.35,.06,.35,.06,paint);
   const shutter=box(scene,x+2.7,1.75,front-.18,3.4,3.4,.22,iron);for(let n=0;n<9;n++)box(scene,shutter.position.x,.25+n*.35,front-.31,3.35,.045,.035,trim);
   if(wing===0)sign(['BLACKWATER FREIGHT','THE COPPER LANTERN','BELL & SONS','NORTH QUAY STORES'][col],x,5,front-.3,Math.min(10,w-1),1.6);
   if(wing===1){const awning=box(scene,x+2.7,3.8,front-.8,4.3,.14,1.5,wood);awning.rotation.x=.12;box(scene,x+2.7,3.6,front-1.4,4.3,.35,.08,trim);}
  }
  // Side façades, drain pipes and raised cornices keep corners from looking like blank boxes.
  for(const side of [-1,1]){
   const x=cx+side*(size/2+.06);for(let n=0;n<5;n++)for(let floor=0;floor<3;floor++){const z=cz-size/2+3+n*(size-6)/4;box(scene,x,3+floor*3.1,z,.18,1.8,1.25,trim);box(scene,x+side*.13,3+floor*3.1,z,.04,1.5,1,((col+n+floor)%6===0)?lit:glass);}
   cylinder(scene,x,5,cz-size/2+.4,.08,10,iron,6);
  }
  for(let n=0;n<3;n++){box(scene,cx-5+n*.95,.55,front-.48,.82,1.05,.75,wood);box(scene,cx-5+n*.95,.55,front-.9,.7,.07,.045,trim);}
  for(let n=0;n<4;n++)box(scene,cx-size/2-.25,.006,front+2+n*7,.42,.035,1.15,iron);
 }
 // Quay stones and rails clearly frame the playable waterfront.
 const water=mat('#233945',.19,.58);box(scene,84,-1.1,-38,340,.15,60,water);
 box(scene,84,-.55,-5.7,185,1.3,1.2,stone);
 for(let i=0;i<25;i++){const x=-5+i*7.5;cylinder(scene,x,.35,-5.6,.095,1,iron,8);box(scene,x+3.7,.7,-5.6,7.5,.075,.075,iron);box(scene,x+3.7,.28,-5.6,7.5,.055,.055,iron);}
 // Ground markings use worn muted paint, and translucent puddles reflect the harbor environment.
 for(let y=0;y<=2;y++)for(let x=0;x<4;x++)for(let n=0;n<5;n++)box(scene,x*M+8+n*6,.006,y*M,1.1,.015,.065,paint);
 for(let x=0;x<=4;x++)for(let y=0;y<2;y++)for(let n=0;n<5;n++)box(scene,x*M,.006,y*M+8+n*6,.065,.015,1.1,paint);
 const puddleMat=mat('#66747b',.08,.65);puddleMat.transparent=true;puddleMat.opacity=.36;puddleMat.depthWrite=false;
 const puddleGeo=new THREE.CircleGeometry(1,12);geometries.push(puddleGeo);
 for(let i=0;i<24;i++){const y=i%3*M,x=4+(i*19)%159;const p=new THREE.Mesh(puddleGeo,puddleMat);p.rotation.x=-Math.PI/2;p.position.set(x,.012,y+Math.sin(i)*3);p.scale.set(1.2+(i%3),.45+(i%4)*.22,1);scene.add(p);}
 const lampPositions:THREE.Vector3[]=[];const glowCanvas=document.createElement('canvas');glowCanvas.width=glowCanvas.height=64;const gx=glowCanvas.getContext('2d')!,gradient=gx.createRadialGradient(32,32,0,32,32,32);gradient.addColorStop(0,'rgba(255,225,165,.65)');gradient.addColorStop(.2,'rgba(238,168,70,.16)');gradient.addColorStop(1,'rgba(238,168,70,0)');gx.fillStyle=gradient;gx.fillRect(0,0,64,64);const glowTexture=new THREE.CanvasTexture(glowCanvas);textures.push(glowTexture);const glowMat=new THREE.SpriteMaterial({map:glowTexture,transparent:true,depthWrite:false,opacity:.65});materials.push(glowMat);const bulb=mat('#d2b077',.3,0,'#ffc27a');bulb.emissiveIntensity=1.2;
 for(let y=0;y<=2;y++)for(let x=0;x<=4;x++){
  const px=x*M+(x===4?-1:1)*(r+.3),pz=y*M+(y===2?-1:1)*(r+.3);cylinder(scene,px,2.5,pz,.065,5,iron,8);cylinder(scene,px,.3,pz,.16,.6,iron,8);box(scene,px,4.95,pz,.4,.65,.4,bulb);box(scene,px,5.34,pz,.68,.12,.68,iron);cylinder(scene,px,5.5,pz,.055,.28,iron,6);const glow=new THREE.Sprite(glowMat);glow.position.set(px,4.95,pz);glow.scale.set(2.6,2.6,1);scene.add(glow);lampPositions.push(new THREE.Vector3(px,4.55,pz));
  if(x===1){const nameplate=sign(c.streets[y]??c.district,px,3.5,pz-.16,2.75,.62);const reverse=new THREE.Mesh(nameplate.geometry,nameplate.material);reverse.position.copy(nameplate.position);reverse.position.z+=.025;reverse.scale.copy(nameplate.scale);reverse.rotation.y=nameplate.rotation.y+Math.PI;scene.add(reverse);}
 }
 const lights=Array.from({length:3},()=>{const l=new THREE.PointLight('#efb06a',45,18,1.5);scene.add(l);return l;});let lampStamp=-Infinity;
 // A small, single-draw layer of drifting rain catches the street lamps.
 const rainCount=260,rainPositions=new Float32Array(rainCount*3);for(let i=0;i<rainCount;i++){rainPositions[i*3]=(i*17.31)%34-17;rainPositions[i*3+1]=(i*7.43)%15;rainPositions[i*3+2]=(i*13.13)%34-17;}const rainGeo=new THREE.BufferGeometry();rainGeo.setAttribute('position',new THREE.BufferAttribute(rainPositions,3));geometries.push(rainGeo);const rainMat=new THREE.PointsMaterial({color:'#9caebd',size:.045,transparent:true,opacity:.24,depthWrite:false});materials.push(rainMat);const rain=new THREE.Points(rainGeo,rainMat);rain.frustumCulled=false;scene.add(rain);const reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
 return {ready:()=>loaded===3,update:(camera:THREE.Camera,seconds:number,dt:number,overview:boolean,performanceMode:boolean)=>{
  if(seconds-lampStamp>.3){lampStamp=seconds;const nearest=lampPositions.slice().sort((a,b)=>a.distanceToSquared(camera.position)-b.distanceToSquared(camera.position));lights.forEach((l,i)=>{l.position.copy(nearest[i]);l.visible=!overview&&(!performanceMode||i===0);});}
  rain.visible=!overview&&!performanceMode&&!reduced;if(rain.visible){rain.position.set(camera.position.x,0,camera.position.z);for(let i=0;i<rainCount;i++)rainPositions[i*3+1]=(rainPositions[i*3+1]-dt*5+15)%15;(rainGeo.attributes.position as THREE.BufferAttribute).needsUpdate=true;}
 },dispose:()=>{disposed=true;}};
}
