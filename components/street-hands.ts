import * as THREE from "three";

export type StreetHandsFrame={
 moving:number;
 sprinting:boolean;
 time:number;
 dt:number;
 weaponName:string|null;
 visible:boolean;
 reducedMotion:boolean;
};

export type StreetHands={
 update:(frame:StreetHandsFrame)=>void;
 shot:()=>void;
 dispose:()=>void;
};

type WeaponMode="none"|"pistol"|"rifle";

// Camera-space view model only. It never reads or mutates gameplay state.
export function createStreetHands(camera:THREE.Camera):StreetHands{
 const geometries=new Set<THREE.BufferGeometry>(),materials=new Set<THREE.Material>();
 const material=(color:string,roughness:number,metalness=0)=>{
  const value=new THREE.MeshStandardMaterial({color,roughness,metalness,depthTest:false,depthWrite:false});materials.add(value);return value;
 };
 const coat=material('#11171a',.9,.08),cuff=material('#9c9789',.72),glove=material('#292621',.68,.05),steel=material('#282e30',.32,.78),darkSteel=material('#171b1d',.42,.68),wood=material('#563923',.76,.08);
 const geometry=<T extends THREE.BufferGeometry>(value:T)=>{geometries.add(value);return value;};
 const mesh=(parent:THREE.Object3D,geo:THREE.BufferGeometry,mat:THREE.Material,order:number)=>{const value=new THREE.Mesh(geo,mat);value.renderOrder=order;value.frustumCulled=false;parent.add(value);return value;};
 const profile=(points:Array<[number,number]>,depth:number)=>{
  const shape=new THREE.Shape();shape.moveTo(points[0][0],points[0][1]);for(let i=1;i<points.length;i++)shape.lineTo(points[i][0],points[i][1]);shape.closePath();
  const geo=geometry(new THREE.ExtrudeGeometry(shape,{depth,steps:1,bevelEnabled:true,bevelSegments:1,bevelSize:.006,bevelThickness:.006,curveSegments:2}));geo.translate(0,0,-depth/2);geo.rotateY(Math.PI/2);return geo;
 };

 const root=new THREE.Group();root.name='street-view-hands';root.visible=false;root.renderOrder=100;camera.add(root);
 const sleeveGeo=geometry(new THREE.CapsuleGeometry(.073,.25,4,8)),handGeo=geometry(new THREE.CapsuleGeometry(.052,.09,4,8)),thumbGeo=geometry(new THREE.CapsuleGeometry(.023,.05,3,7)),cuffGeo=geometry(new THREE.CylinderGeometry(.068,.073,.045,8,1));
 function arm(side:-1|1){
  const group=new THREE.Group();root.add(group);
  const sleeve=mesh(group,sleeveGeo,coat,110);sleeve.position.y=-.015;
  const shirt=mesh(group,cuffGeo,cuff,111);shirt.position.set(0,.18,-.008);
  const fist=mesh(group,handGeo,glove,114);fist.position.set(0,.255,-.025);fist.rotation.x=Math.PI/2;fist.scale.set(1.04,1,1.12);
  const thumb=mesh(group,thumbGeo,glove,115);thumb.position.set(side*-.044,.238,-.058);thumb.rotation.set(.88,0,side*.5);
  return group;
 }
 const leftArm=arm(-1),rightArm=arm(1);

 const pistol=new THREE.Group();pistol.visible=false;root.add(pistol);
 const pistolSlide=profile([[-.06,.015],[.225,.015],[.245,.05],[.195,.095],[-.055,.095],[-.075,.06]],.07);mesh(pistol,pistolSlide,steel,112);
 const pistolGrip=mesh(pistol,geometry(new THREE.CapsuleGeometry(.041,.12,4,8)),glove,112);pistolGrip.position.set(0,-.065,.035);pistolGrip.rotation.x=-.22;pistolGrip.scale.set(.82,1,.72);
 const pistolBarrel=mesh(pistol,geometry(new THREE.CylinderGeometry(.017,.017,.27,8,1)),darkSteel,113);pistolBarrel.rotation.x=Math.PI/2;pistolBarrel.position.set(0,.057,-.13);
 const pistolGuard=mesh(pistol,geometry(new THREE.TorusGeometry(.038,.008,5,10,Math.PI*1.55)),steel,113);pistolGuard.position.set(0,-.006,-.005);pistolGuard.rotation.set(0,0,.7);

 const rifle=new THREE.Group();rifle.visible=false;root.add(rifle);
 const rifleReceiver=profile([[-.095,.01],[.19,.01],[.205,.075],[.135,.105],[-.08,.095],[-.11,.055]],.09);mesh(rifle,rifleReceiver,darkSteel,112);
 const rifleStock=profile([[-.34,-.065],[-.075,-.005],[-.045,.075],[-.105,.105],[-.33,.025],[-.39,-.025]],.082);mesh(rifle,rifleStock,wood,112);
 const rifleBarrel=mesh(rifle,geometry(new THREE.CylinderGeometry(.014,.018,.55,8,1)),steel,112);rifleBarrel.rotation.x=Math.PI/2;rifleBarrel.position.set(0,.067,-.37);
 const rifleForegrip=mesh(rifle,geometry(new THREE.CapsuleGeometry(.034,.19,3,8)),wood,113);rifleForegrip.rotation.x=Math.PI/2;rifleForegrip.position.set(0,.025,-.235);rifleForegrip.scale.x=.82;
 const rifleGrip=mesh(rifle,geometry(new THREE.CapsuleGeometry(.036,.105,3,8)),wood,113);rifleGrip.position.set(0,-.065,.035);rifleGrip.rotation.x=-.25;rifleGrip.scale.set(.82,1,.72);
 const rifleSight=mesh(rifle,geometry(new THREE.CylinderGeometry(.009,.009,.06,6,1)),steel,113);rifleSight.position.set(0,.12,-.08);

 const poses:{[K in WeaponMode]:{left:[number,number,number,number];right:[number,number,number,number];weapon:[number,number,number]}}={
  none:{left:[-.3,-.42,-.55,-.32],right:[.3,-.42,-.55,.32],weapon:[0,0,0]},
  pistol:{left:[-.34,-.47,-.55,-.2],right:[.19,-.4,-.52,.11],weapon:[.19,-.125,-.59]},
  rifle:{left:[-.18,-.41,-.59,-.06],right:[.2,-.43,-.51,.1],weapon:[.035,-.13,-.61]},
 };
 const target=new THREE.Vector3();pistol.position.set(...poses.pistol.weapon);rifle.position.set(...poses.rifle.weapon);
 let disposed=false,recoil=0,motion=0,reduced=false,mode:WeaponMode='none';
 const armPose=(group:THREE.Group,values:[number,number,number,number],amount:number)=>{group.position.lerp(target.set(values[0],values[1],values[2]),amount);group.rotation.z+=(values[3]-group.rotation.z)*amount;};
 const setMode=(next:WeaponMode)=>{mode=next;pistol.visible=next==='pistol';rifle.visible=next==='rifle';};
 const initial=poses.none;leftArm.position.set(...initial.left.slice(0,3) as [number,number,number]);leftArm.rotation.z=initial.left[3];rightArm.position.set(...initial.right.slice(0,3) as [number,number,number]);rightArm.rotation.z=initial.right[3];
 return {
  update:({moving,sprinting,time,dt,weaponName,visible,reducedMotion})=>{
   if(disposed)return;root.visible=visible;if(!visible){motion=0;return;}
   const next:WeaponMode=!weaponName?'none':/(rifle|carbine)/i.test(weaponName)?'rifle':'pistol';if(next!==mode)setMode(next);
   reduced=reducedMotion;const step=Math.max(0,Math.min(.1,dt)),blend=1-Math.exp(-step*11);motion+=(Math.max(0,Math.min(1,moving))-motion)*blend;recoil*=Math.exp(-step*16);
   const pace=sprinting?11:8,amplitude=reducedMotion?0:.0065*motion*(sprinting?1.55:1),side=Math.sin(time*pace)*amplitude,drop=Math.abs(Math.cos(time*pace)) * amplitude;
   root.position.set(side,-drop,recoil*.035);root.rotation.set(recoil*-.07,0,-side*.55);
   const pose=poses[mode];armPose(leftArm,pose.left,blend);armPose(rightArm,pose.right,blend);
   const weapon=mode==='rifle'?rifle:pistol;if(mode!=='none'){weapon.position.lerp(target.set(...pose.weapon),blend);weapon.rotation.x=-recoil*(mode==='rifle'?.055:.11);weapon.rotation.z=side*.45;}
  },
  shot:()=>{if(!disposed&&!reduced&&root.visible)recoil=1;},
  dispose:()=>{if(disposed)return;disposed=true;camera.remove(root);geometries.forEach(value=>value.dispose());materials.forEach(value=>value.dispose());root.clear();}
 };
}
