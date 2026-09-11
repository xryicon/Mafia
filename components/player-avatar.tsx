"use client";
import {useState} from "react";
export const defaultPortrait="/art/command-portrait.jpg";
export function PlayerAvatar({src,name="",className="",size=42}:{src?:string|null;name?:string;className?:string;size?:number}){
 const [failed,setFailed]=useState<string|null>(null);
 const safe=src&&(src.startsWith("https://")||src.startsWith("/art/"))?src:defaultPortrait;
 return <img className={className} src={failed===safe?defaultPortrait:safe} alt={name?name+"'s profile picture":""} width={size} height={size} referrerPolicy="no-referrer" onError={()=>setFailed(safe)}/>;
}

