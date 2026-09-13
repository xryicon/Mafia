"use client";
import {useCallback,useEffect,useRef,useState} from "react";
import {createClient} from "@/lib/supabase/client";
import type {RangeState} from "@/lib/range";
type Receipt={id:string;action:string;server_time:string;reload_started_at?:string;reload_ready_at?:string};
type Request={action:string;payload:Record<string,unknown>};
export function useRange(initial:RangeState){
 const [receipt,setReceipt]=useState<Receipt|null>(null),[data,setData]=useState(initial),[working,setWorking]=useState(false),[notice,setNotice]=useState(""),[failed,setFailed]=useState(false),[retry,setRetry]=useState<Request|null>(null);
 const awarded=useRef(initial.stats.xp_earned??0),lock=useRef(false),alive=useRef(true),sequence=useRef(0),clockBase=useRef({server:Date.parse(initial.server_time),local:0});
 const clock=useCallback(()=>clockBase.current.server+(clockBase.current.local?performance.now()-clockBase.current.local:0),[]);
 const accept=useCallback((next:RangeState,sent:number)=>{clockBase.current={server:Date.parse(next.server_time)+(performance.now()-sent)/2,local:performance.now()};setData(next);if(awarded.current!==(next.stats.xp_earned??0)){awarded.current=next.stats.xp_earned??0;window.dispatchEvent(new Event("blackwater:game"));}},[]);
 const refresh=useCallback(async()=>{if(lock.current)return;const seq=++sequence.current,sent=performance.now();const r=await createClient().rpc("range_state");if(r.error||!r.data)throw new Error("The range could not refresh. Try again.");if(alive.current&&sequence.current===seq)accept(r.data,sent);},[accept]);
 useEffect(()=>{alive.current=true;clockBase.current.local=performance.now();void refresh().catch(e=>{setFailed(true);setNotice(e.message);});const update=()=>{if(!document.hidden)void refresh().catch(()=>{});};const interval=setInterval(update,15000);window.addEventListener("focus",update);return()=>{alive.current=false;sequence.current++;clearInterval(interval);window.removeEventListener("focus",update);};},[refresh]);
 const run=async(request:Request)=>{if(lock.current)return false;lock.current=true;sequence.current++;setWorking(true);setNotice("");setFailed(false);const sent=performance.now();let uncertain=true;
 try{const r=await createClient().rpc("range_action",{p_action:request.action,p_payload:request.payload});if(r.error)throw new Error("The shot reply was interrupted. Retry safely before firing again.");uncertain=false;setRetry(null);if(r.data?.error)throw new Error(r.data.error);if(alive.current){accept(r.data.state,sent);setNotice(r.data.message);setReceipt({id:String(request.payload.request_id),action:request.action,server_time:r.data.state.server_time,reload_started_at:r.data.reload_started_at,reload_ready_at:r.data.reload_ready_at});}return true;
 }catch(e){if(alive.current){setFailed(true);setNotice(e instanceof Error?e.message:"Range action failed.");if(uncertain)setRetry(request);}return false;}finally{lock.current=false;if(alive.current)setWorking(false);}};
 return {data,working,notice,failed,retry,receipt,busy:working||!!retry,clock,refresh:()=>void refresh().catch(e=>{setFailed(true);setNotice(e.message);}),act:(action:string,payload:Record<string,unknown>)=>retry?Promise.resolve(false):run({action,payload:{...payload,request_id:crypto.randomUUID()}}),retryAction:()=>retry?run(retry):Promise.resolve(false)};
}
