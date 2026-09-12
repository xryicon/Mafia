"use client";
import {useCallback,useEffect,useRef,useState} from "react";
import {createClient} from "@/lib/supabase/client";
import type {InventoryState} from "@/lib/inventory";
type Request={rpc:"inventory_action"|"bin_diving_action";action:string;payload:Record<string,unknown>};
export function useInventory(initial:InventoryState){
 const [data,setData]=useState(initial),[working,setWorking]=useState(false),[notice,setNotice]=useState(""),[failed,setFailed]=useState(false),[retry,setRetry]=useState<Request|null>(null),[reading,setReading]=useState(false);
 const lock=useRef(false),sequence=useRef(0),offset=useRef(0),alive=useRef(true);
 const refresh=useCallback(async(next=offset.current)=>{const seq=++sequence.current;setReading(true);try{const r=await createClient().rpc("inventory_state",{p_offset:next});if(r.error||!r.data)throw new Error("Inventory could not refresh. Try again.");if(alive.current&&seq===sequence.current){setData(r.data);offset.current=next;}}finally{if(alive.current&&seq===sequence.current)setReading(false);}},[]);
 useEffect(()=>{alive.current=true;const update=()=>{if(!document.hidden&&!lock.current)void refresh().catch(()=>{if(alive.current){setFailed(true);setNotice("Live updates paused. Refresh to reconnect.");}});};const timer=setInterval(update,20000);window.addEventListener("focus",update);return()=>{alive.current=false;sequence.current++;clearInterval(timer);window.removeEventListener("focus",update);};},[refresh]);
 const run=async(request:Request)=>{if(lock.current)return false;lock.current=true;sequence.current++;setReading(false);setWorking(true);setNotice("");setFailed(false);let uncertain=true;
 try{const r=await createClient().rpc(request.rpc,{p_action:request.action,p_payload:request.payload});if(r.error)throw new Error("The reply was interrupted. Retry safely to confirm the result.");uncertain=false;setRetry(null);if(r.data?.error)throw new Error(r.data.error);setNotice(r.data.message);window.dispatchEvent(new Event("blackwater:game"));try{await refresh(0);}catch{setNotice(r.data.message+" Refresh to see your inventory.");}return true;
 }catch(e){setFailed(true);setNotice(e instanceof Error?e.message:"Action could not be completed.");if(uncertain)setRetry(request);return false;}finally{lock.current=false;setWorking(false);}};
 return {data,working,reading,notice,failed,retry,busy:working||!!retry,clear:()=>{setNotice("");setFailed(false);},
 refresh:(page?:number)=>void refresh(page).catch(e=>{setFailed(true);setNotice(e.message);}),
 act:(action:string,payload:Record<string,unknown>,rpc:Request["rpc"]="inventory_action")=>retry?Promise.resolve(false):run({rpc,action,payload:{...payload,request_id:crypto.randomUUID()}}),retryAction:()=>retry?run(retry):Promise.resolve(false)};
}
