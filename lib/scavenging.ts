import type {VehicleModel,StreetOperations} from "./street-operations";
export type StreetTarget={id:string;node:number;kind:"bin"|"car";ready_at:string|null;vehicle?:VehicleModel|null};
export type StreetPosition=[number,number];
export type PolicePatrol={id:string;route_points:StreetPosition[];epoch:number;seconds_per_block:number;radius:number};
export type StreetSession={district_id:string;node:number;path:number[];route_points?:StreetPosition[];departed_at:string;arrives_at:string;pending:null|{id:string;target_id:string;kind:"bin"|"car";started_at:string;ready_at:string;success_percent:number;xp:number;mode?:"theft"|"event";vehicle?:VehicleModel;event_kind?:string}};
export type ScavengingState={session:StreetSession|null;targets:StreetTarget[];streets:string[];settings:Record<string,number>;patrols?:PolicePatrol[];caught?:boolean;operations?:StreetOperations;recent:{kind:string;opened:boolean;xp:number;created_at:string}[]};
// Presentation coordinates aligned to the overhead artwork. Server node IDs and travel rules are unchanged.
export const STREET_COLUMNS=[73,289,497,711,928] as const;
export const STREET_ROWS=[114,344,607] as const;
export const streetPoint=(node:number)=>({x:STREET_COLUMNS[node%5],y:STREET_ROWS[Math.floor(node/5)]});
export function mapPoint([x,y]:StreetPosition){
 const axis=(value:number,points:readonly number[])=>{const index=Math.min(Math.floor(value),points.length-2);return points[index]+(points[index+1]-points[index])*(value-index);};
 return {x:axis(x,STREET_COLUMNS),y:axis(y,STREET_ROWS)};
}
export function nearestStreetPosition(x:number,y:number):StreetPosition{
 const coordinate=(value:number,points:readonly number[])=>{for(let i=1;i<points.length;i++)if(value<=points[i])return Math.max(0,i-1+(value-points[i-1])/(points[i]-points[i-1]));return points.length-1;};
 const gx=coordinate(x,STREET_COLUMNS),gy=coordinate(y,STREET_ROWS);
 const horizontal:StreetPosition=[gx,Math.round(gy)],vertical:StreetPosition=[Math.round(gx),gy];
 const a=mapPoint(horizontal),b=mapPoint(vertical);
 return Math.hypot(x-a.x,y-a.y)<=Math.hypot(x-b.x,y-b.y)?horizontal:vertical;
}
export const sessionDestination=(session:StreetSession):StreetPosition=>session.route_points?.at(-1)??[session.node%5,Math.floor(session.node/5)];
export function patrolPosition(patrol:PolicePatrol,now:number):StreetPosition{
 const blocks=patrol.route_points.slice(1).reduce((sum,p,i)=>sum+Math.abs(p[0]-patrol.route_points[i][0])+Math.abs(p[1]-patrol.route_points[i][1]),0);
 const duration=blocks*patrol.seconds_per_block;if(duration<=0)return patrol.route_points[0]??[0,0];
 const phase=((now/1000-patrol.epoch)%duration+duration)%duration;
 return routePosition(patrol.route_points,phase/duration);
}
export function routePosition(points:StreetPosition[],progress:number):StreetPosition{
 const length=(a:StreetPosition,b:StreetPosition)=>Math.abs(a[0]-b[0])+Math.abs(a[1]-b[1]);
 let remaining=points.slice(1).reduce((sum,p,i)=>sum+length(points[i],p),0)*Math.max(0,Math.min(1,progress));
 for(let i=1;i<points.length;i++){const a=points[i-1],b=points[i],distance=length(a,b);if(distance>0&&remaining<=distance)return [a[0]+(b[0]-a[0])*remaining/distance,a[1]+(b[1]-a[1])*remaining/distance];remaining-=distance;}
 return points.at(-1)??[0,0];
}
export function nearestStreetNode(x:number,y:number){
 const closest=(values:readonly number[],value:number)=>values.reduce((best,v,i)=>Math.abs(v-value)<Math.abs(values[best]-value)?i:best,0);
 return closest(STREET_ROWS,y)*5+closest(STREET_COLUMNS,x);
}
export function walkingPosition(session:StreetSession,now:number){
 const path=session.path.length?session.path:[session.node];
 const duration=Date.parse(session.arrives_at)-Date.parse(session.departed_at);
 const progress=duration>0?Math.max(0,Math.min(1,(now-Date.parse(session.departed_at))/duration)):1;
 if(session.route_points?.length)return mapPoint(routePosition(session.route_points,progress));
 const step=progress*(path.length-1),index=Math.floor(step),a=streetPoint(path[index]),b=streetPoint(path[Math.min(index+1,path.length-1)]);
 return {x:a.x+(b.x-a.x)*(step-index),y:a.y+(b.y-a.y)*(step-index)};
}
