export type StreetTarget={id:string;node:number;kind:"bin"|"car";ready_at:string|null};
export type StreetSession={district_id:string;node:number;path:number[];departed_at:string;arrives_at:string;pending:null|{id:string;target_id:string;kind:"bin"|"car";started_at:string;ready_at:string;success_percent:number;xp:number}};
export type ScavengingState={session:StreetSession|null;targets:StreetTarget[];streets:string[];settings:Record<string,number>;recent:{kind:string;opened:boolean;xp:number;created_at:string}[]};
// Presentation coordinates aligned to the overhead artwork. Server node IDs and travel rules are unchanged.
export const STREET_COLUMNS=[73,289,497,711,928] as const;
export const STREET_ROWS=[114,344,607] as const;
export const streetPoint=(node:number)=>({x:STREET_COLUMNS[node%5],y:STREET_ROWS[Math.floor(node/5)]});
export function nearestStreetNode(x:number,y:number){
 const closest=(values:readonly number[],value:number)=>values.reduce((best,v,i)=>Math.abs(v-value)<Math.abs(values[best]-value)?i:best,0);
 return closest(STREET_ROWS,y)*5+closest(STREET_COLUMNS,x);
}
export function walkingPosition(session:StreetSession,now:number){
 const path=session.path.length?session.path:[session.node];
 const duration=Date.parse(session.arrives_at)-Date.parse(session.departed_at);
 const progress=duration>0?Math.max(0,Math.min(1,(now-Date.parse(session.departed_at))/duration)):1;
 const step=progress*(path.length-1),index=Math.floor(step),a=streetPoint(path[index]),b=streetPoint(path[Math.min(index+1,path.length-1)]);
 return {x:a.x+(b.x-a.x)*(step-index),y:a.y+(b.y-a.y)*(step-index)};
}
