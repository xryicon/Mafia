// One scoring plane shared by rendered paper and ray-to-score conversion.
// The database continues to accept the same 0..100 coordinates and shot clock.
export const rangePlane={width:8,height:3,centreY:1.65,z:-12};
export function rangeWorldPoint(x:number,y:number){return{x:(x/100-.5)*rangePlane.width,y:rangePlane.centreY+(.5-y/100)*rangePlane.height,z:rangePlane.z};}
export function rangeScorePoint(x:number,y:number){return{x:(x/rangePlane.width+.5)*100,y:(.5-(y-rangePlane.centreY)/rangePlane.height)*100};}
export function rangeReloadPose(now:number,started:string|null|undefined,ready:string|null|undefined){
 if(!started||!ready)return{progress:0,tilt:0,magazine:0,hand:0,active:false};
 const start=Date.parse(started),end=Date.parse(ready);if(!Number.isFinite(start)||!Number.isFinite(end)||end<=start||now>=end)return{progress:1,tilt:0,magazine:0,hand:0,active:false};
 const p=Math.max(0,Math.min(1,(now-start)/(end-start))),smooth=(v:number)=>{const n=Math.max(0,Math.min(1,v));return n*n*(3-2*n);};
 return{progress:p,tilt:smooth(p/.18)*(1-smooth((p-.78)/.22)),magazine:smooth((p-.15)/.2)*(1-smooth((p-.6)/.2)),hand:Math.sin(p*Math.PI),active:true};
}
