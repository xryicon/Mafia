import type {StreetPosition} from "./scavenging";
// The renderer uses metres; authority and the aerial map share district block coordinates.
export const STREET_METRES=42;
export const FOOT_ROAD_HALF_WIDTH=.13;
export function onStreet([x,y]:StreetPosition,width=FOOT_ROAD_HALF_WIDTH){
 return Number.isFinite(x)&&Number.isFinite(y)&&x>=0&&x<=4&&y>=0&&y<=2&&(Math.abs(x-Math.round(x))<=width||Math.abs(y-Math.round(y))<=width);
}
export function streetSight(a:StreetPosition,b:StreetPosition,width=FOOT_ROAD_HALF_WIDTH){
 const steps=Math.max(1,Math.ceil(Math.hypot(b[0]-a[0],b[1]-a[1])/.025));
 for(let i=0;i<=steps;i++)if(!onStreet([a[0]+(b[0]-a[0])*i/steps,a[1]+(b[1]-a[1])*i/steps],width))return false;
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
