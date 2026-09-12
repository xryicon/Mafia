"use client";
import {useCallback,useEffect,useRef,useState} from "react";
import {createClient} from "@/lib/supabase/client";
import type {RefineryState,RefineryReceipt} from "@/lib/refineries";
type Request={action:string;payload:Record<string,unknown>};
export function useRefinery(initial?:RefineryState){
 const [data,setData]=useState(initial),[busy,setBusy]=useState(false),[notice,setNotice]=useState(""),[failed,setFailed]=useState(false),[retry,setRetry]=useState<Request|null>(null),[result,setResult]=useState<RefineryReceipt|null>(null);
 const lock=useRef(false),sequence=useRef(0),alive=useRef(true),offset=useRef(initial?Date.parse(initial.server_time)-Date.now():0);
 const [now,setNow]=useState(initial?Date.parse(initial.server_time):Date.now());
 const refresh=useCallback(async()=>{
  const version=++sequence.current;const r=await createClient().rpc("refinery_state");
  if(r.error||!r.data)throw new Error("The refineries could not refresh. Try again.");
  if(alive.current&&version===sequence.current){setData(r.data);offset.current=Date.parse(r.data.server_time)-Date.now();setNow(Date.now()+offset.current);}
 },[]);
 useEffect(()=>{alive.current=true;if(!initial)void refresh().catch(e=>{setFailed(true);setNotice(e.message);});
  const tick=setInterval(()=>setNow(Date.now()+offset.current),1000);
  const poll=()=>{if(!document.hidden&&!lock.current)void refresh().catch(()=>{setFailed(true);setNotice("Live updates paused. Refresh to reconnect.");});};
  const timer=setInterval(poll,20000);window.addEventListener("focus",poll);
  return()=>{alive.current=false;sequence.current++;clearInterval(tick);clearInterval(timer);window.removeEventListener("focus",poll);};
 },[refresh,initial]);
 const run=async(action:string,payload:Record<string,unknown>={}):Promise<boolean>=>{
  if(lock.current||!data)return false;lock.current=true;++sequence.current;setBusy(true);setNotice("");setFailed(false);
  const request={action,payload:{...payload,season_id:payload.season_id??data.season.id,request_id:payload.request_id??crypto.randomUUID()}};
  let uncertain=true;
  try{
   const r=await createClient().rpc("refinery_action",{p_action:action,p_payload:request.payload});
   if(r.error)throw new Error("The response was interrupted. Retry the same request to safely confirm the result.");
   uncertain=false;setRetry(null);if(r.data?.error)throw new Error(r.data.error);
   if(r.data?.receipt){setResult(r.data.receipt);}
   setNotice(r.data?.message??"Saved.");window.dispatchEvent(new Event("blackwater:game"));
   try{await refresh();}catch{setNotice((r.data?.message??"Saved.")+" Refresh to see your updated totals.");}
   return true;
  }catch(e){setFailed(true);setNotice(e instanceof Error?e.message:"Could not finish this action.");if(uncertain)setRetry(request);return false;}
  finally{lock.current=false;setBusy(false);}
 };
 return {data,now,busy:busy||!!retry,working:busy,notice,failed,retry,result,
  act:(action:string,payload:Record<string,unknown>={})=>retry?Promise.resolve(false):run(action,payload),
  retryAction:()=>retry?run(retry.action,retry.payload):Promise.resolve(false),
  refresh:()=>void refresh().catch(e=>{setFailed(true);setNotice(e.message);})};
}
