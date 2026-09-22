import type {StreetPosition} from "./scavenging";
// The renderer uses metres; authority and the aerial map share district block coordinates.
export const STREET_METRES=42;
export const FOOT_ROAD_HALF_WIDTH=.13;
export function onStreet([x,y]:StreetPosition,width=FOOT_ROAD_HALF_WIDTH){
 return Number.isFinite(x)&&Number.isFinite(y)&&x>=0&&x<=4&&y>=0&&y<=2&&(Math.abs(x-Math.round(x))<=width||Math.abs(y-Math.round(y))<=width);
}
export function streetSight(a:StreetPosition,b:StreetPosition,width=FOOT_ROAD_HALF_WIDTH){
 if(!onStreet(a,width)||!onStreet(b,width))return false;
 // Exact segment/rectangle clipping: a tiny diagonal across a corner must not escape sampling.
 for(let x=0;x<4;x++)for(let y=0;y<2;y++){
  let lo=0,hi=1,miss=false;
  for(const axis of [0,1] as const){const min=(axis===0?x:y)+width,max=(axis===0?x:y)+1-width,d=b[axis]-a[axis];
   if(Math.abs(d)<1e-12){if(a[axis]<=min||a[axis]>=max){miss=true;break;}}
   else{const t0=(min-a[axis])/d,t1=(max-a[axis])/d;lo=Math.max(lo,Math.min(t0,t1));hi=Math.min(hi,Math.max(t0,t1));}
  }
  if(!miss&&hi>lo+1e-12)return false;
 }
 return true;
}
export function footStep(origin:StreetPosition,dx:number,dy:number,seconds:number,secondsPerBlock:number,width=FOOT_ROAD_HALF_WIDTH):StreetPosition{
 const scale=Math.max(1,Math.hypot(dx,dy)),distance=Math.max(0,Math.min(.8,seconds))/Math.max(1,secondsPerBlock),steps=Math.max(1,Math.ceil(distance/.018));
 let point:StreetPosition=[...origin];
 for(let i=0;i<steps;i++){
  const x=Math.max(0,Math.min(4,point[0]+dx/scale*distance/steps)),y=Math.max(0,Math.min(2,point[1]+dy/scale*distance/steps));
  if(onStreet([x,y],width))point=[x,y];else if(onStreet([x,point[1]],width))point=[x,point[1]];else if(onStreet([point[0],y],width))point=[point[0],y];
 }
 if(!streetSight(origin,point,width))point=streetSight(origin,[point[0],origin[1]],width)?[point[0],origin[1]]:[origin[0],point[1]];
 return point;
}
export function nearestStreetCenter([x,y]:StreetPosition):StreetPosition{return Math.abs(x-Math.round(x))<Math.abs(y-Math.round(y))?[Math.round(x),y]:[x,Math.round(y)];}
