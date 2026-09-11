"use client";
import {useEffect,useState} from "react";
import {createClient} from "@/lib/supabase/client";
import {TelegramOfficeControls} from "@/components/telegram-office";
import type {TelegramState} from "@/lib/telegrams";
export function TelegramAdmin(){
 const [data,setData]=useState<TelegramState|null>(null),[notice,setNotice]=useState("");
 async function refresh(){const r=await createClient().rpc("telegram_state");if(r.error){setNotice("The office could not be loaded.");return;}setData(r.data);}
 useEffect(()=>{void refresh();},[]);
 async function send(action:string,payload:Record<string,string>){try{const r=await createClient().rpc("telegram_manage",{p_action:action,p_payload:payload});if(r.error||r.data?.error)throw new Error(r.data?.error||r.error?.message);setNotice(r.data.message);await refresh();return true;}catch(e){setNotice(e instanceof Error?e.message:"Office update failed.");return false;}}
 return <section className="tg-admin"><h2>City Telegram Office</h2><p>One unique strategic property. Private messages are excluded from this panel.</p>{notice&&<p role="status" className="game-notice">{notice}</p>}{data?.office.can_manage?<TelegramOfficeControls office={data.office} send={send} admin/>:!data?<p>Loading office…</p>:<p>Owner access required.</p>}</section>;
}
export function TelegramEvidence({caseId}:{caseId:string}){
 const [evidence,setEvidence]=useState<{subject:string;body:string;sender_name:string;recipient_name:string;created_at:string}|null>(null),[notice,setNotice]=useState(""),[busy,setBusy]=useState(false);
 async function inspect(){setBusy(true);try{const r=await createClient().rpc("telegram_evidence",{p_case:caseId});if(r.error||r.data?.error)throw new Error(r.data?.error||r.error?.message);setEvidence(r.data);setNotice("");}catch(e){setNotice(e instanceof Error?e.message:"Evidence unavailable.");}finally{setBusy(false);}}
 return <section><p>Set this report to investigating before opening the specifically reported telegram. Access is recorded.</p><button disabled={busy} onClick={()=>void inspect()}>Inspect reported telegram</button>{notice&&<p role="alert">{notice}</p>}{evidence&&<div className="tg-evidence"><strong>{evidence.subject}</strong><p>{evidence.sender_name} → {evidence.recipient_name}</p><p className="preserve-text">{evidence.body}</p></div>}</section>;
}

