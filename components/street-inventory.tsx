"use client";
import {useEffect,useRef,useState} from "react";
import {createClient} from "@/lib/supabase/client";
import type {InventoryState} from "@/lib/inventory";
import {InventoryWorkspace} from "./inventory-workspace";
export function StreetInventory({close}:{close:()=>void}){
 const dialog=useRef<HTMLDialogElement>(null),[data,setData]=useState<InventoryState|null>(null),[error,setError]=useState(false);
 useEffect(()=>{dialog.current?.showModal();const abort=new AbortController();void Promise.resolve(createClient().rpc('inventory_state',{p_offset:0}).abortSignal(abort.signal)).then(r=>{if(abort.signal.aborted)return;if(r.error||!r.data)setError(true);else setData(r.data);}).catch(()=>{if(!abort.signal.aborted)setError(true);});return()=>abort.abort();},[]);
 return <dialog ref={dialog} className="fp-inventory-dialog" aria-label="Inventory and equipment" onCancel={e=>{e.preventDefault();close();}} onKeyDown={e=>{if(e.key==='Tab'&&!e.shiftKey&&!(e.target instanceof HTMLInputElement)&&!(e.target instanceof HTMLSelectElement)&&!(e.target instanceof HTMLTextArea)){e.preventDefault();close();}}}><button className="fp-inventory-close" onClick={close}>Return to streets · Tab</button>{data?<InventoryWorkspace initial={data}/>:<p role="status">{error?'Inventory could not load. Close and try again.':'Loading your inventory and equipment…'}</p>}</dialog>;
}
