"use client";
import {useCallback,useEffect,useRef,useState} from "react";
import {RangeAudio} from "@/lib/range-audio";
const key="blackwater-range-audio";
export function useRangeAudio(){
 const [enabled,setEnabled]=useState(true),[volume,setVolume]=useState(35),[error,setError]=useState("");const engine=useRef<RangeAudio|null>(null),prefs=useRef({enabled:true,volume:35}),alive=useRef(true);
 useEffect(()=>{alive.current=true;try{const p=JSON.parse(localStorage.getItem(key)||"null");if(p&&typeof p.enabled==="boolean"&&Number.isFinite(p.volume)){prefs.current={enabled:p.enabled,volume:Math.max(0,Math.min(100,p.volume))};setEnabled(prefs.current.enabled);setVolume(prefs.current.volume);}}catch{/* Storage may be unavailable. */}const visibility=()=>engine.current?.visibility();document.addEventListener("visibilitychange",visibility);return()=>{alive.current=false;document.removeEventListener("visibilitychange",visibility);engine.current?.close();engine.current=null;};},[]);
 const unlock=useCallback(()=>{if(!engine.current)engine.current=new RangeAudio();const p=prefs.current;void engine.current.unlock(p.enabled,p.volume/100).then(()=>{if(alive.current)setError("");}).catch(()=>{if(alive.current)setError("Sound is unavailable. You can still use the range.");});},[]);
 const change=(next:{enabled:boolean;volume:number})=>{prefs.current=next;setEnabled(next.enabled);setVolume(next.volume);try{localStorage.setItem(key,JSON.stringify(next));}catch{/* Keep this visit's preference. */}engine.current?.set(next.enabled,next.volume/100);if(next.enabled)unlock();};
 return {enabled,volume,error,unlock,toggle:()=>change({...prefs.current,enabled:!prefs.current.enabled}),setVolume:(volume:number)=>change({...prefs.current,volume}),shot:()=>engine.current?.shot(),reload:(ms:number,elapsed:number)=>engine.current?.reload(ms,elapsed)};
}
