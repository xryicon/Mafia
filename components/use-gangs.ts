"use client";
import {useCallback,useEffect,useRef,useState} from "react";
import {createClient} from "@/lib/supabase/client";
import type {GangWorkspaceState,GangCommand} from "@/lib/gangs";
export function useGangs(initial:GangWorkspaceState){
 const [data,setData]=useState(initial),[working,setWorking]=useState(false),[reading,setReading]=useState(false),[notice,setNotice]=useState(""),[failed,setFailed]=useState(false),[retry,setRetry]=useState<GangCommand|null>(null);
 const lock=useRef(false),alive=useRef(true),seq=useRef(0),offset=useRef(0),gang=useRef(initial.selected?.id??null);
 const refresh=useCallback(async(page=offset.current)=>{const n=++seq.current;setReading(true);try{const r=await createClient().rpc("gang_workspace",{p_gang:gang.current,p_offset:page});if(r.error||!r.data)throw new Error("The gang panel could not refresh. Try again.");if(alive.current&&n===seq.current){setData(r.data);offset.current=page;}}finally{if(alive.current&&n===seq.current)setReading(false);}},[]);
 useEffect(()=>{alive.current=true;const update=()=>{if(!document.hidden&&!lock.current)void refresh().catch(e=>{setFailed(true);setNotice(e.message);});};const timer=setInterval(update,30000);window.addEventListener("focus",update);return()=>{alive.current=false;seq.current++;clearInterval(timer);window.removeEventListener("focus",update);};},[refresh]);
 const run=async(command:GangCommand)=>{
  if(lock.current)return false;lock.current=true;seq.current++;setWorking(true);setNotice("");setFailed(false);setReading(false);let uncertain=true;
  try{const r=await createClient().rpc("gang_action",{p_action:command.action,p_payload:command.payload});if(r.error||!r.data)throw new Error("The response was interrupted. Retry safely to confirm the result.");
   uncertain=false;setRetry(null);if(r.data.error)throw new Error(r.data.error);setNotice(r.data.message);window.dispatchEvent(new Event("blackwater:game"));
   if(command.action==="create")gang.current=r.data.gang_id;
   try{await refresh(0);}catch{setNotice(r.data.message+" Refresh to see the latest changes.");}return true;
  }catch(e){setFailed(true);setNotice(e instanceof Error?e.message:"The action could not be completed.");if(uncertain)setRetry(command);return false;}
  finally{lock.current=false;setWorking(false);}
 };
 return {data,working,reading,notice,failed,retry,busy:working||!!retry,act:(c:GangCommand)=>retry?Promise.resolve(false):run(c),retryAction:()=>retry?run(retry):Promise.resolve(false),refresh:(page?:number)=>void refresh(page).catch(e=>{setFailed(true);setNotice(e.message);})};
}
