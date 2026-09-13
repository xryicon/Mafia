"use client";

import {useEffect,useState} from "react";

type CountdownParts={days:number;hours:number;minutes:number;seconds:number};

function splitTime(milliseconds:number):CountdownParts{
 const total=Math.max(0,Math.floor(milliseconds/1000));
 return {days:Math.floor(total/86400),hours:Math.floor(total/3600)%24,minutes:Math.floor(total/60)%60,seconds:total%60};
}

function utcLabel(startsAt:string){
 return new Intl.DateTimeFormat("en-US",{day:"numeric",month:"long",year:"numeric",hour:"2-digit",minute:"2-digit",hour12:false,timeZone:"UTC",timeZoneName:"short"}).format(new Date(startsAt));
}

export function BetaCountdown({startsAt,serverTime}:{startsAt:string;serverTime:string}){
 const start=Date.parse(startsAt),serverStart=Date.parse(serverTime);
 const [now,setNow]=useState(serverStart),[dateLabel,setDateLabel]=useState(()=>utcLabel(startsAt));
 useEffect(()=>{
  const browserStart=Date.now();
  const tick=()=>setNow(serverStart+(Date.now()-browserStart));
  tick();const timer=window.setInterval(tick,1000);
  setDateLabel(new Intl.DateTimeFormat("en-US",{weekday:"long",day:"numeric",month:"long",year:"numeric",hour:"2-digit",minute:"2-digit",timeZoneName:"short"}).format(new Date(startsAt)));
  return()=>window.clearInterval(timer);
 },[serverStart,startsAt]);
 const remaining=start-now,parts=splitTime(remaining),open=remaining<=0;
 return <section className="beta-countdown" aria-labelledby="beta-launch-title" data-feature="closed-beta-countdown">
  <div className="beta-countdown-heading"><span className="red-dot"/><div><p>Closed beta starting on</p><h2 id="beta-launch-title">{dateLabel}</h2></div></div>
  {open?<p className="beta-open">Closed beta is now open.</p>:<div className="beta-clock" role="timer" aria-label={`${parts.days} days, ${parts.hours} hours, ${parts.minutes} minutes and ${parts.seconds} seconds until closed beta`}>
   {([['DAYS',parts.days],['HOURS',parts.hours],['MIN',parts.minutes],['SEC',parts.seconds]] as const).map(([label,value])=><span key={label}><strong>{String(value).padStart(2,"0")}</strong><small>{label}</small></span>)}
  </div>}
 </section>;
}
