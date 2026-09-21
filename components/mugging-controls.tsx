"use client";
import {useCallback,useEffect,useRef,useState} from "react";
import {createClient} from "@/lib/supabase/client";
import {RobberyPanel} from "./robbery-panel";
import type {RobberyState} from "@/lib/robbery";
type Request={action:string;payload:Record<string,unknown>};
export function MuggingControls({selection,onAvailability}:{selection?:{id:string;key:number};onAvailability?:(ids:string[])=>void}){
 const [data,setData]=useState<RobberyState>(),[busy,setBusy]=useState(false),[notice,setNotice]=useState(""),[failed,setFailed]=useState(false),[retry,setRetry]=useState<Request|null>(null),[now,setNow]=useState(Date.now());
 const lock=useRef(false),alive=useRef(true),sequence=useRef(0),offset=useRef(0);
 const refresh=useCallback(async()=>{
  const version=++sequence.current;const r=await createClient().rpc("robbery_state");
  if(r.error||!r.data)throw new Error("Mugging could not refresh. Try again.");
  if(alive.current&&version===sequence.current){setData(r.data);offset.current=Date.parse(r.data.server_time)-Date.now();setNow(Date.now()+offset.current);}
 },[]);
 useEffect(()=>{
  alive.current=true;let reading=false;
  const poll=()=>{if(document.hidden||lock.current||reading)return;reading=true;void refresh().catch(e=>{if(alive.current){setFailed(true);setNotice(e.message);}}).finally(()=>{reading=false;});};
  poll();const timer=setInterval(poll,10000),tick=setInterval(()=>setNow(Date.now()+offset.current),1000);
  window.addEventListener("focus",poll);window.addEventListener("blackwater:game",poll);document.addEventListener("visibilitychange",poll);
  return()=>{alive.current=false;++sequence.current;clearInterval(timer);clearInterval(tick);window.removeEventListener("focus",poll);window.removeEventListener("blackwater:game",poll);document.removeEventListener("visibilitychange",poll);};
 },[refresh]);
 useEffect(()=>{onAvailability?.(busy||retry?[]:data?.targets.filter(t=>!t.protected_until||Date.parse(t.protected_until)<=now).map(t=>t.id)??[]);},[data,busy,retry,now,onAvailability]);
 const run=async(action:string,payload:Record<string,unknown>={}):Promise<boolean>=>{
  if(lock.current||!data)return false;lock.current=true;++sequence.current;setBusy(true);setFailed(false);setNotice("");
  const request={action,payload:{...payload,season_id:payload.season_id??data.season_id,request_id:payload.request_id??crypto.randomUUID()}};let uncertain=true;
  try{
   const r=await createClient().rpc("robbery_action",{p_action:action.replace(/^rob_/,""),p_payload:request.payload});
   if(r.error||!r.data)throw new Error("The response was interrupted. Retry the same request to safely confirm the result.");
   uncertain=false;setRetry(null);if(r.data.error)throw new Error(r.data.error);
   setNotice(r.data.message??"Attempt resolved.");window.dispatchEvent(new Event("blackwater:game"));
   try{await refresh();}catch{setNotice((r.data.message??"Attempt resolved.")+" Refresh to see your updated totals.");}return true;
  }catch(e){setFailed(true);setNotice(e instanceof Error?e.message:"Could not resolve the attempt.");if(uncertain)setRetry(request);else{try{await refresh();}catch{/* Keep the last confirmed state visible. */}}return false;}
  finally{lock.current=false;setBusy(false);}
 };
 return <section className="robbery-controls" aria-label="Mugging">
  {!data&&!notice&&<p>Loading mugging…</p>}
  <RobberyPanel selection={selection} data={data} now={now} busy={busy||!!retry} blocked={!!retry} act={(action,payload)=>retry?Promise.resolve(false):run(action,payload)}/>
  <button className="button small ghost" disabled={busy} onClick={()=>void refresh().then(()=>{if(!retry){setNotice("");setFailed(false);}}).catch(e=>{setFailed(true);setNotice(e.message);})}>Refresh mugging</button>
  {notice&&<p className={"notice mugging-notice"+(failed?" error":"")} role={failed?"alert":"status"}>{notice}</p>}
  {retry&&<button className="button small" disabled={busy} onClick={()=>void run(retry.action,retry.payload)}>Retry safely</button>}
 </section>;
}
