import {GameIcon} from "./game-icon";
import {displayedHealth,type PlayerVitals} from "@/lib/vitals";
export function PlayerVitalBars({vitals,now}:{vitals:PlayerVitals|null;now:number}){
 const health=vitals?displayedHealth(vitals,now):null;
 const boosted=vitals&&health!==null&&health>vitals.health_max;
 const number=(n:number)=>Math.ceil(n).toLocaleString("en-US");
 return <>{[["health","Health","heart",health,vitals?.health_max],["armour","Armour","shield",vitals?.armour??null,vitals?.armour_max]].map(([kind,label,icon,value,max])=>{
  const current=typeof value==="number"?value:null,limit=typeof max==="number"?max:null,isBoost=kind==="health"&&boosted;
  const ceiling=isBoost?vitals!.health_cap:limit;
  return <div className={"command-vital command-vital-"+kind} key={String(kind)}>
   <dt><GameIcon name={String(icon)}/>{label}</dt><dd>
    <span className="command-vital-number">{current===null||limit===null?"—":<>{number(current)} <small>/ {number(limit)}</small>{isBoost&&<b title="Temporary health above your normal maximum">+{number(current-limit)}</b>}</>}</span>
    <span className={"command-vital-track"+(isBoost?" boosted":"")} role={current===null?"img":"meter"} aria-label={String(label)+(current===null?" unavailable":"")} aria-valuemin={current===null?undefined:0} aria-valuemax={current===null?undefined:ceiling!} aria-valuenow={current===null?undefined:Math.ceil(current)} aria-valuetext={current===null?undefined:number(current)+" of "+number(limit!)+(isBoost?", temporary boost":"")}>
     <i style={{width:current!==null&&limit?Math.max(0,Math.min(100,current/limit*100))+"%":"0%"}}/>
     {isBoost&&<em style={{width:Math.min(100,(current!-limit!)/(vitals!.health_cap-limit!)*100)+"%"}}/>}
    </span>
   </dd>
  </div>;
 })}</>;
}
