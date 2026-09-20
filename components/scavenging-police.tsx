import {mapPoint,patrolPosition,type PolicePatrol,type StreetPosition} from '@/lib/scavenging';
export function ScavengingPolice({patrols,now}:{patrols:PolicePatrol[];now:number}){
 return <g className="scav-police" pointerEvents="none" role="group" aria-label={`${patrols.length} police patrols`}>
  {patrols.map((patrol,i)=>{const position=patrolPosition(patrol,now),point=mapPoint(position);
   const area=Array.from({length:32},(_,index)=>{const angle=index/32*Math.PI*2;const p=mapPoint([Math.max(0,Math.min(4,position[0]+Math.cos(angle)*patrol.radius)),Math.max(0,Math.min(2,position[1]+Math.sin(angle)*patrol.radius))] as StreetPosition);return `${p.x},${p.y}`;}).join(' ');
   return <g key={patrol.id} aria-label={`Police patrol ${i+1}`}><polygon className="scav-police-area" points={area}/><g transform={`translate(${point.x} ${point.y})`}><rect className="scav-police-car" x="-15" y="-9" width="30" height="18" rx="5"/><path d="M-6 -8v16M6 -8v16" stroke="#c5d9df" strokeWidth="2"/><circle cx="0" cy="0" r="4" fill="#9dbacb"/><text x="0" y="-18" textAnchor="middle">POLICE {i+1}</text></g></g>;
  })}
 </g>;
}
