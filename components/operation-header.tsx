import type {ReactNode} from "react";
import {GameIcon} from "@/components/game-icon";

export function OperationHeader({title,kicker,motto,icon,status,caption}:{title:string;kicker:string;motto:string;icon:string;status:ReactNode;caption:string}){
 return <header className="operation-header">
  <div><p className="eyebrow">BLACKWATER / {kicker}</p><h1>{title}</h1><p className="operation-motto">{motto}</p></div>
  <div className="operation-header-status"><GameIcon name={icon} size={31}/><div><span>THE CITY AT WORK</span><strong>{status}</strong><small>{caption}</small></div></div>
 </header>;
}
