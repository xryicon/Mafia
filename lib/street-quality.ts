export type StreetQuality = "auto" | "high" | "performance";
export function streetPixelRatio(width:number,height:number,dpr:number,quality:StreetQuality,coarse:boolean,adaptive=1){
 const cap=quality==='high'?1.75:quality==='performance'?.8:coarse?1:1.3;
 const pixels=quality==='high'?2400000:quality==='performance'?650000:coarse?850000:1400000;
 return Math.max(.1,Math.min(dpr,cap,Math.sqrt(pixels/Math.max(1,width*height)))*(quality==='auto'?adaptive:1));
}
// Sustained frame samples only: do not react to a texture upload, hidden tab or a single long frame.
export function adaptStreetResolution(scale:number,frameMs:number,samples:number){
 if(samples<3||frameMs*samples<2000)return scale;
 if(frameMs>27)return Math.max(.6,Math.round((scale-.1)*10)/10);
 if(frameMs<18)return Math.min(1,Math.round((scale+.05)*100)/100);
 return scale;
}
