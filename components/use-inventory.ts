"use client";
import {useCallback,useEffect,useRef,useState} from "react";
import {createClient} from "@/lib/supabase/client";
import type {InventoryState} from "@/lib/inventory";
type Request={rpc:"inventory_action"|"bin_diving_action";action:string;payload:Record<string,unknown>};
export function useInventory(initial:InventoryState){
 const [data,setData]=useState(initial),[working,setWorking]=useState(false),[notice,setNotice]=useState(""),[failed,setFailed]=useState(false),[retry,setRetry]=useState<Request|null>(null),[reading,setReading]=useState(false);
 const lock=useRef(false),sequence=useRef(0),offset=useRef(initial.offset),alive=useRef(true);
 const pendingRead=useRef<{page:number;sequence:number;promise:Promise<void>}|null>(null);
 const refresh=useCallback((next=offset.current,afterAction=false):Promise<void>=>{
  if(lock.current&&!afterAction)return Promise.resolve();
  const existing=pendingRead.current;
  if(!afterAction&&existing?.page===next&&existing.sequence===sequence.current)return existing.promise;
  const seq=++sequence.current;setReading(true);
  const entry={page:next,sequence:seq,promise:Promise.resolve()};pendingRead.current=entry;
  entry.promise=(async()=>{try{
   const r=await createClient().rpc("inventory_state",{p_offset:next});
   if(r.error||!r.data)throw new Error("Inventory could not refresh. Try again.");
   if(alive.current&&seq===sequence.current){setData(r.data);offset.current=next;}
  }catch(e){if(alive.current&&seq===sequence.current)throw e;}
  finally{if(pendingRead.current===entry)pendingRead.current=null;if(alive.current&&seq===sequence.current)setReading(false);}})();
  return entry.promise;
 },[]);
 useEffect(()=>{alive.current=true;const update=()=>{if(!document.hidden&&!lock.current)void refresh().catch(()=>{if(alive.current){setFailed(true);setNotice("Live updates paused. Refresh to reconnect.");}});};const timer=setInterval(update,20000);window.addEventListener("focus",update);document.addEventListener("visibilitychange",update);return()=>{alive.current=false;sequence.current++;clearInterval(timer);window.removeEventListener("focus",update);document.removeEventListener("visibilitychange",update);};},[refresh]);
 const run=async(request:Request)=>{if(lock.current)return false;lock.current=true;sequence.current++;setReading(false);setWorking(true);setNotice("");setFailed(false);let uncertain=true;
 try{const r=await createClient().rpc(request.rpc,{p_action:request.action,p_payload:request.payload});if(r.error)throw new Error("The reply was interrupted. Retry safely to confirm the result.");uncertain=false;setRetry(null);if(r.data?.error)throw new Error(r.data.error);setNotice(r.data.message);window.dispatchEvent(new Event("blackwater:game"));try{await refresh(0,true);}catch{setNotice(r.data.message+" Refresh to see your inventory.");}return true;
 }catch(e){setFailed(true);setNotice(e instanceof Error?e.message:"Action could not be completed.");if(uncertain)setRetry(request);return false;}finally{lock.current=false;setWorking(false);}};
 return {data,working,reading,notice,failed,retry,busy:working||!!retry,clear:()=>{setNotice("");setFailed(false);},
 refresh:(page?:number)=>void refresh(page).catch(e=>{setFailed(true);setNotice(e.message);}),
 act:(action:string,payload:Record<string,unknown>,rpc:Request["rpc"]="inventory_action")=>retry?Promise.resolve(false):run({rpc,action,payload:{...payload,request_id:crypto.randomUUID()}}),retryAction:()=>retry?run(retry):Promise.resolve(false)};
}
