"use client";
import {useCallback,useEffect,useRef,useState} from "react";
import {createClient} from "@/lib/supabase/client";
import type {CraftState} from "@/lib/crafting";
type CraftRequest={action:string;payload:Record<string,unknown>};
export function useCrafting(initial:CraftState){
 const [data,setData]=useState(initial),[busy,setBusy]=useState(false),[notice,setNotice]=useState(""),[failed,setFailed]=useState(false),[retry,setRetry]=useState<CraftRequest|null>(null);
 const lock=useRef(false),alive=useRef(true),sequence=useRef(0);
 const refresh=useCallback(async()=>{const seq=++sequence.current;const r=await createClient().rpc("crafting_state");if(r.error||!r.data)throw new Error("Crafting could not refresh. Try again.");if(alive.current&&seq===sequence.current)setData(r.data);},[]);
 useEffect(()=>{alive.current=true;const update=()=>{if(!document.hidden&&!lock.current)void refresh().catch(()=>{if(alive.current){setFailed(true);setNotice("Live updates paused. Refresh to reconnect.");}});};const timer=setInterval(update,10000);window.addEventListener("focus",update);return()=>{alive.current=false;sequence.current++;clearInterval(timer);window.removeEventListener("focus",update);};},[refresh]);
 const run=async(request:CraftRequest)=>{if(lock.current)return false;lock.current=true;sequence.current++;setBusy(true);setNotice("");setFailed(false);let uncertain=true;try{
 const r=await createClient().rpc("crafting_action",{p_action:request.action,p_payload:request.payload});if(r.error)throw new Error("The reply was interrupted. Retry safely to confirm the result.");uncertain=false;setRetry(null);if(r.data?.error)throw new Error(r.data.error);setNotice(r.data.message);window.dispatchEvent(new Event("blackwater:game"));try{await refresh();}catch{setNotice(r.data.message+" Refresh to see the latest stock.");}return true;
 }catch(e){setFailed(true);setNotice(e instanceof Error?e.message:"Crafting failed.");if(uncertain)setRetry(request);return false;}finally{lock.current=false;setBusy(false);}};
 return {data,busy:busy||!!retry,working:busy,notice,failed,retry,refresh:()=>void refresh().catch(e=>{setNotice(e.message);setFailed(true);}),clear:()=>{setNotice("");setFailed(false);},
 act:(action:string,payload:Record<string,unknown>)=>retry?Promise.resolve(false):run({action,payload:{...payload,request_id:crypto.randomUUID()}}),retryAction:()=>retry?run(retry):Promise.resolve(false)};
}
