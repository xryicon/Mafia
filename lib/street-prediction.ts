import {footStep,onStreet,streetSight} from "./first-person-movement";
import {routePosition,type StreetPosition,type StreetSession} from "./scavenging";

export type StreetDirection={dx:number;dy:number;sprint:boolean};
export type StreetCorrection={point:StreetPosition;remaining:StreetPosition};

export function motionActive(input:StreetDirection){return Math.hypot(input.dx,input.dy)>.001;}
export function meaningfulDirectionChange(a:StreetDirection,b:StreetDirection,threshold=.12){
 const aMoving=motionActive(a),bMoving=motionActive(b);if(!aMoving&&!bMoving)return false;
 if(aMoving!==bMoving||a.sprint!==b.sprint)return true;
 return Math.hypot(a.dx-b.dx,a.dy-b.dy)>=threshold;
}
export function streetSessionPosition(session:StreetSession,now:number):StreetPosition{
 const start=Date.parse(session.departed_at),end=Date.parse(session.arrives_at);
 return routePosition(session.route_points??[[session.node%5,Math.floor(session.node/5)]],end>start?(now-start)/(end-start):1);
}
// The snapshot is stamped on the server just before its response. Half the measured
// round trip estimates how far the authoritative route advances before receipt.
export function acknowledgedStreetPosition(session:StreetSession,serverTime:number,roundTripMs:number):StreetPosition{
 return streetSessionPosition(session,serverTime+Math.max(0,roundTripMs)/2);
}
export function predictionDeadline(receivedAt:number,session:StreetSession,serverTime:number,roundTripMs:number){
 const estimatedReceiveTime=serverTime+Math.max(0,roundTripMs)/2;
 return receivedAt+Math.max(0,Date.parse(session.arrives_at)-estimatedReceiveTime);
}
export function predictionSeconds(frameStart:number,frameEnd:number,deadline:number){
 return Math.max(0,Math.min(frameEnd,deadline)-Math.min(frameStart,deadline))/1000;
}
export function predictionDeadlineForInput(deadline:number,now:number,leaseMs:number,previous:StreetDirection,next:StreetDirection){
 if(!motionActive(next))return 0;
 return motionActive(previous)?deadline:Math.max(deadline,now+Math.max(0,leaseMs));
}
export function streetSendInterval(ratePerMinute:number){
 const rate=Number.isFinite(ratePerMinute)&&ratePerMinute>0?ratePerMinute:360;
 return 63_000/rate;
}
export function predictStreetPosition(point:StreetPosition,input:StreetDirection,frameStart:number,frameEnd:number,deadline:number,secondsPerBlock:number,width:number){
 const seconds=predictionSeconds(frameStart,frameEnd,deadline);
 return seconds>0?footStep(point,input.dx,input.dy,seconds,secondsPerBlock,width):point;
}
export function beginStreetCorrection(predicted:StreetPosition,authoritative:StreetPosition,width:number,snapDistance=.25):StreetCorrection{
 const error:StreetPosition=[authoritative[0]-predicted[0],authoritative[1]-predicted[1]];
 if(Math.hypot(...error)>snapDistance||!streetSight(predicted,authoritative,width))return {point:[...authoritative],remaining:[0,0]};
 return {point:predicted,remaining:error};
}
export function applyStreetCorrection(point:StreetPosition,remaining:StreetPosition,seconds:number,width:number):StreetCorrection{
 const fraction=Math.min(1,Math.max(0,seconds)*8),applied:StreetPosition=[remaining[0]*fraction,remaining[1]*fraction];
 const next:StreetPosition=[point[0]+applied[0],point[1]+applied[1]];
 if(!onStreet(next,width)||!streetSight(point,next,width))return {point,remaining:[0,0]};
 return {point:next,remaining:[remaining[0]-applied[0],remaining[1]-applied[1]]};
}
