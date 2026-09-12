"use client";
import {useCallback,useEffect,useRef,useState} from "react";
import {createClient} from "@/lib/supabase/client";
import type {BankState,BankTransfer} from "@/lib/bank";
export function useBank(initial:BankState){
 const [data,setData]=useState(initial),[working,setWorking]=useState(false),[notice,setNotice]=useState(""),[failed,setFailed]=useState(false),[retry,setRetry]=useState<BankTransfer|null>(null),[reading,setReading]=useState(false);
 const alive=useRef(true),lock=useRef(false),sequence=useRef(0),offset=useRef(0);
 const refresh=useCallback(async(next=offset.current)=>{
  const seq=++sequence.current;setReading(true);
  try{const r=await createClient().rpc("bank_state",{p_offset:next});if(r.error||!r.data)throw new Error("The bank could not refresh. Try again.");if(alive.current&&seq===sequence.current){setData(r.data);offset.current=next;}}
  finally{if(alive.current&&seq===sequence.current)setReading(false);}
 },[]);
 useEffect(()=>{alive.current=true;const update=()=>{if(!document.hidden&&!lock.current)void refresh().catch(()=>{setFailed(true);setNotice("Live updates paused. Refresh to reconnect.");});};
  const timer=setInterval(update,20000);window.addEventListener("focus",update);return()=>{alive.current=false;sequence.current++;clearInterval(timer);window.removeEventListener("focus",update);};
 },[refresh]);
 const run=async(request:BankTransfer)=>{
  if(lock.current)return false;lock.current=true;sequence.current++;setReading(false);setWorking(true);setFailed(false);setNotice("");let uncertain=true;
  try{
   const r=await createClient().rpc("bank_action",{p_action:request.action,p_payload:request.payload});
   if(r.error)throw new Error("The response was interrupted. Retry this transfer safely to confirm its result.");
   uncertain=false;setRetry(null);if(r.data?.error)throw new Error(r.data.error);
   setNotice(r.data.message);window.dispatchEvent(new Event("blackwater:game"));
   try{await refresh(0);}catch{setNotice(r.data.message+" Refresh to see your balances.");}return true;
  }catch(e){setFailed(true);setNotice(e instanceof Error?e.message:"Transfer could not be completed.");if(uncertain)setRetry(request);return false;}
  finally{lock.current=false;setWorking(false);}
 };
 return {data,notice,failed,working,reading,retry,busy:working||!!retry,
  transfer:(request:BankTransfer)=>retry?Promise.resolve(false):run(request),
  retryTransfer:()=>retry?run(retry):Promise.resolve(false),
  refresh:(page?:number)=>void refresh(page).catch(e=>{setFailed(true);setNotice(e.message);})};
}
