export type StreetTarget={id:string;node:number;kind:"bin"|"car";ready_at:string|null};
export type StreetSession={district_id:string;node:number;path:number[];departed_at:string;arrives_at:string;pending:null|{id:string;target_id:string;kind:"bin"|"car";started_at:string;ready_at:string;success_percent:number;xp:number}};
export type ScavengingState={session:StreetSession|null;targets:StreetTarget[];streets:string[];settings:Record<string,number>;recent:{kind:string;opened:boolean;xp:number;created_at:string}[]};
export const streetPoint=(node:number)=>({x:100+(node%5)*200,y:130+Math.floor(node/5)*210});
export function walkingPosition(session:StreetSession,now:number){
 const path=session.path.length?session.path:[session.node];
 const duration=Date.parse(session.arrives_at)-Date.parse(session.departed_at);
 const progress=duration>0?Math.max(0,Math.min(1,(now-Date.parse(session.departed_at))/duration)):1;
 const step=progress*(path.length-1),index=Math.floor(step),a=streetPoint(path[index]),b=streetPoint(path[Math.min(index+1,path.length-1)]);
 return {x:a.x+(b.x-a.x)*(step-index),y:a.y+(b.y-a.y)*(step-index)};
}
