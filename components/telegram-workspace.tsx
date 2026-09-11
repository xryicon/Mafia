"use client";
import {useCallback,useEffect,useRef,useState,type FormEvent} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase/client";
import {GameIcon} from "@/components/game-icon";
import {TelegramOffice,TelegramOfficeControls} from "@/components/telegram-office";
import {telegramFee,telegramDay,telegramTime,type TelegramState,type TelegramDraft} from "@/lib/telegrams";
const folders=[["inbox","Inbox","mail"],["sent","Sent","arrow"],["drafts","Drafts","ledger"],["archive","Archive","inventory"],["starred","Starred","respect"],["reports","Reports","shield"]];
function Seal({name}:{name:string}){return <span className="tg-seal" aria-hidden="true">{name.slice(0,2).toUpperCase()}</span>;}
export function TelegramWorkspace({initial}:{initial:TelegramState}){
 const [data,setData]=useState(initial),[folder,setFolder]=useState("inbox"),[thread,setThread]=useState<string|null>(null),[before,setBefore]=useState<string|null>(null),[offset,setOffset]=useState(0),[compose,setCompose]=useState(false),[showOffice,setShowOffice]=useState(false);
 const [recipient,setRecipient]=useState(""),[subject,setSubject]=useState(""),[body,setBody]=useState(""),[draftId,setDraftId]=useState<string|null>(null),[candidates,setCandidates]=useState<{id:string;username:string}[]>([]);
 const [busy,setBusy]=useState(false),[notice,setNotice]=useState(""),[failed,setFailed]=useState(false),[report,setReport]=useState<string|null>(null),[uncertain,setUncertain]=useState(false);
 const pending=useRef<Record<string,unknown>|null>(null),sequence=useRef(0),modal=useRef<HTMLDialogElement>(null),end=useRef<HTMLDivElement>(null);
 const refresh=useCallback(async()=>{
  const seq=++sequence.current;
  const r=await createClient().rpc("telegram_state",{p_thread:thread,p_folder:folder,p_offset:offset,p_before:before});
  if(seq!==sequence.current)return;
  if(r.error||!r.data){setNotice("Connection interrupted. Refresh your mailbox to reconnect.");setFailed(true);return;}
  setData(r.data);
 },[thread,folder,offset,before]);
 useEffect(()=>{void refresh();const timer=setInterval(()=>{if(!document.hidden&&!busy)void refresh();},15000);return()=>{clearInterval(timer);sequence.current++;};},[refresh,busy]);
 useEffect(()=>{if(showOffice)modal.current?.showModal();else modal.current?.close();},[showOffice]);
 useEffect(()=>{if(!before)end.current?.scrollIntoView({block:"nearest"});},[data.messages.length,thread,before]);
 useEffect(()=>{
  if(!compose||recipient.trim().length<2){setCandidates([]);return;}
  let active=true;const timer=setTimeout(async()=>{const r=await createClient().rpc("player_directory",{p_search:recipient,p_online:false,p_offset:0});if(active&&r.data)setCandidates(r.data.players.filter((p:{id:string})=>p.id!==data.player_id));},250);
  return()=>{active=false;clearTimeout(timer);};
 },[recipient,compose,data.player_id]);
 function newTelegram(d?:TelegramDraft){if(uncertain)return;setThread(null);setBefore(null);setCompose(true);setRecipient(d?.recipient||"");setSubject(d?.subject||"");setBody(d?.body||"");setDraftId(d?.id||null);setReport(null);setNotice("");}
 function choose(id:string){if(uncertain)return;setThread(id);setBefore(null);setCompose(false);setBody("");setReport(null);setNotice("");}
 async function act(action:string,payload:Record<string,unknown>={},rpc="telegram_action"){
  setBusy(true);setNotice("");setFailed(false);
  try{const r=await createClient().rpc(rpc,{p_action:action,p_payload:payload});if(r.error||r.data?.error)throw new Error(r.data?.error||r.error?.message);setNotice(r.data.message);await refresh();window.dispatchEvent(new Event("blackwater:game"));return r.data;}
  catch(e){setFailed(true);setNotice(e instanceof Error?e.message:"Unable to complete this action.");await refresh();return null;}finally{setBusy(false);}
 }
 async function sendMessage(e:FormEvent<HTMLFormElement>){
  e.preventDefault();setBusy(true);setNotice("");setFailed(false);
  pending.current??={request_id:crypto.randomUUID(),thread_id:compose?null:thread,recipient,subject,body,fee:data.office.fee,season_id:data.season.id,draft_id:draftId};
  try{
   const r=await createClient().rpc("telegram_action",{p_action:"send",p_payload:pending.current});
   if(r.error)throw new Error("Delivery confirmation was interrupted. Retry safely to confirm the same telegram.");
   if(r.data?.error){pending.current=null;setUncertain(false);setFailed(true);setNotice(r.data.error);await refresh();return;}
   pending.current=null;setUncertain(false);setNotice(r.data.message);setBody("");setDraftId(null);setCompose(false);setBefore(null);setThread(r.data.thread_id);await refresh();window.dispatchEvent(new Event("blackwater:game"));
  }catch(e){setUncertain(true);setFailed(true);setNotice(e instanceof Error?e.message:"Retry to confirm delivery.");}finally{setBusy(false);}
 }
 async function saveDraft(){const r=await act("draft",{id:draftId,recipient,subject,body});if(r?.draft_id)setDraftId(r.draft_id);}
 const blocked=data.thread&&data.blocks.some(b=>b.id===data.thread!.other_id),canSend=data.office.available&&data.season.status==="open"&&!blocked&&data.cash>=data.office.fee;
 const active=data.threads.find(t=>t.id===thread),reading=!!thread&&!compose;
 return <div className="tg-page">
 <header className="tg-banner"><div><p className="eyebrow"><span/>A PLAYER-DRIVEN CRIME ECONOMY</p><span className="tg-city-name">BLACKWATER</span><p className="tg-motto">“Business always finds a way.”</p></div><div className="tg-banner-note">POWER<br/>MOVES<br/>PEOPLE</div></header>
 {notice&&<div className={"tg-notice "+(failed?"error":"")} role={failed?"alert":"status"}>{notice}</div>}
 <div className="tg-layout">
 <aside className="tg-panel tg-sidebar"><h1>Telegrams</h1><button className="tg-gold tg-new" disabled={uncertain} onClick={()=>newTelegram()}><GameIcon name="mail"/>New Telegram</button>
 <nav aria-label="Telegram folders">{folders.map(([id,name,icon])=><button key={id} className={folder===id?"active":""} aria-current={folder===id?"page":undefined} onClick={()=>{if(uncertain)return;setFolder(id);setOffset(0);setThread(null);setCompose(false);setBefore(null);}}><GameIcon name={icon}/><span>{name}</span>{id==="inbox"&&data.unread>0&&<b>{data.unread}</b>}{id==="drafts"&&data.drafts.length>0&&<small>{data.drafts.length}</small>}</button>)}</nav>
 <div className="tg-list-heading"><span>{folder==="drafts"?"DRAFTS":folder==="reports"?"REPORTS":"CONVERSATIONS"}</span><button title="Refresh mailbox" aria-label="Refresh mailbox" onClick={()=>void refresh()}><GameIcon name="refresh" size={16}/></button></div>
 <div className="tg-conversations">{folder==="drafts"?data.drafts.map(d=><button key={d.id} onClick={()=>newTelegram(d)}><Seal name={d.recipient||"?"}/><span><strong>{d.recipient||"Unaddressed"}</strong><small>{d.subject||"Untitled draft"}</small></span></button>):folder==="reports"?data.reports.map(r=><article className="tg-report-item" key={r.id}><strong>Telegram report</strong><small>{r.status} · {telegramDay(r.created_at)}</small><p>{r.response||"Awaiting a moderator response."}</p></article>):data.threads.map(t=><button key={t.id} className={thread===t.id?"selected":""} onClick={()=>choose(t.id)}><Seal name={t.other_name}/><span><strong>{t.other_name}</strong><small>{t.subject}</small><small className="tg-excerpt">{t.excerpt}</small></span><span className="tg-thread-time">{telegramTime(t.last_at)}{t.unread>0&&<b>{t.unread}</b>}</span></button>)}
 {((folder==="drafts"&&!data.drafts.length)||(folder==="reports"&&!data.reports.length)||(!["drafts","reports"].includes(folder)&&!data.threads.length))&&<p className="tg-list-empty">No {folder==="drafts"?"drafts":folder==="reports"?"reports":"conversations"} here yet.</p>}
 </div>
 {!["drafts","reports"].includes(folder)&&<div className="tg-pagination">{offset>0&&<button onClick={()=>setOffset(v=>Math.max(0,v-50))}>← Previous</button>}{data.threads.length===50&&<button onClick={()=>setOffset(v=>v+50)}>More →</button>}</div>}
 {data.blocks.length>0&&<details className="tg-blocks"><summary>Blocked players ({data.blocks.length})</summary>{data.blocks.map(b=><p key={b.id}>{b.name}<button disabled={busy} onClick={()=>void act("unblock",{player_id:b.id})}>Unblock</button></p>)}</details>}
 </aside>
 <section className="tg-panel tg-correspondence" aria-label="Private telegrams">
 <div className="tg-breadcrumb">TELEGRAMS / {compose?"NEW TELEGRAM":reading?"CONVERSATION":"PRIVATE CORRESPONDENCE"}</div>
 {reading&&data.thread&&<header className="tg-thread-header"><Seal name={data.thread.other_name}/><div><h2>{data.thread.other_name}</h2><p>{data.thread.subject}</p><Link href={"/players/"+data.thread.other_id}>View player →</Link></div><div className="tg-thread-tools"><button aria-label={active?.starred?"Unstar conversation":"Star conversation"} title="Star conversation" disabled={busy} onClick={()=>void act("star",{thread_id:thread})}>☆</button><details><summary aria-label="Conversation options">⋮</summary><div><button disabled={busy} onClick={()=>void act("archive",{thread_id:thread})}>{active?.archived?"Restore conversation":"Archive conversation"}</button><button disabled={busy} onClick={()=>void act(blocked?"unblock":"block",{player_id:data.thread!.other_id})}>{blocked?"Unblock player":"Block player"}</button></div></details></div></header>}
 {reading?<div className="tg-message-feed">{data.messages.length===50&&<button className="tg-older" onClick={()=>setBefore(data.messages[0].id)}>Load older telegrams</button>}{before&&<button className="tg-older" onClick={()=>setBefore(null)}>Return to latest</button>}
 {data.messages.map((m,i)=><div key={m.id}>{(i===0||telegramDay(m.created_at)!==telegramDay(data.messages[i-1].created_at))&&<div className="tg-date"><span>{telegramDay(m.created_at)} · UTC</span></div>}<article className={"tg-message "+(m.sender_id===data.player_id?"outgoing":"incoming")}><Seal name={m.sender_name}/><div><div className="tg-message-meta"><strong>{m.sender_id===data.player_id?"You":m.sender_name}</strong><time dateTime={m.created_at}>{telegramTime(m.created_at)}</time></div><p>{m.body}</p>{m.recipient_id===data.player_id&&<button className="tg-report-link" onClick={()=>setReport(report===m.id?null:m.id)}>Report telegram</button>}</div></article>{report===m.id&&<form className="tg-report-form" onSubmit={async e=>{e.preventDefault();const reason=String(new FormData(e.currentTarget).get("reason"));if(await act("report",{message_id:m.id,reason}))setReport(null);}}><label>Why are you reporting this telegram?<textarea name="reason" minLength={3} maxLength={2000} required/></label><button disabled={busy}>Submit report</button><button type="button" onClick={()=>setReport(null)}>Cancel</button></form>}</div>)}<div ref={end}/></div>:!compose?<div className="tg-welcome"><span className="tg-welcome-seal"><GameIcon name="mail" size={42}/></span><span className="eyebrow">THE CITY IS LISTENING. YOUR INBOX IS PRIVATE.</span><h2>Every empire<br/>begins with a message.</h2><p>Strike a deal. Find a partner. Make your next move.<br/>Private telegrams, delivered instantly across Blackwater.</p><button className="tg-gold" onClick={()=>newTelegram()}>Write your first telegram <GameIcon name="arrow"/></button><div className="tg-welcome-fee"><span>{data.office.name}</span><strong>{telegramFee(data.office.fee)} <small>per telegram</small></strong></div></div>:<div className="tg-compose-heading"><span className="eyebrow">PRIVATE CORRESPONDENCE</span><h2>Make your next move.</h2><p>A direct line to the people who move this city.</p></div>}
 {(compose||reading)&&<form className="tg-composer" onSubmit={e=>void sendMessage(e)}><fieldset disabled={busy||uncertain}>{compose&&<><label>Recipient<input list="telegram-recipients" name="recipient" value={recipient} onChange={e=>setRecipient(e.target.value)} placeholder="Search a player username" maxLength={48} required autoComplete="off"/><datalist id="telegram-recipients">{candidates.map(p=><option key={p.id} value={p.username}/>)}</datalist></label><label>Subject<input name="subject" value={subject} onChange={e=>setSubject(e.target.value)} maxLength={data.limits.subject} placeholder="Give your telegram a subject" required/></label></>}
 <label className="tg-body-label">{compose?"Message":"Your reply"}<textarea name="message" value={body} onChange={e=>setBody(e.target.value)} placeholder="Write your telegram…" maxLength={data.limits.body} required rows={compose?7:3}/></label></fieldset>
 <div className="tg-send-terms"><GameIcon name="shield" size={16}/><span>{data.office.name}<small>Delivery: Instant · Fee: <b>{telegramFee(data.office.fee)}</b></small></span></div>
 {!data.office.available&&<p className="tg-unavailable">Telegram service is currently unavailable.</p>}{data.season.status!=="open"&&<p className="tg-unavailable">Sending is paused while the season is {data.season.status}.</p>}{blocked&&<p className="tg-unavailable">Unblock this player to resume the conversation.</p>}{data.cash<data.office.fee&&<p className="tg-unavailable">Not enough cash for the current delivery fee.</p>}
 <div className="tg-compose-actions">{compose&&<div><button type="button" disabled={busy||uncertain} onClick={()=>void saveDraft()}>Save draft</button>{draftId&&<button type="button" disabled={busy||uncertain} onClick={async()=>{if(await act("delete_draft",{id:draftId})){setDraftId(null);setCompose(false);}}}>Discard</button>}</div>}<button className="tg-gold" disabled={busy||(!uncertain&&!canSend)}><GameIcon name="arrow"/>{busy?"Sending…":uncertain?"Retry delivery":"Send Telegram"}</button></div></form>}
 </section>
 <TelegramOffice office={data.office} onManage={()=>setShowOffice(true)}/>
 </div>
 <dialog className="tg-modal" ref={modal} onCancel={()=>setShowOffice(false)} aria-labelledby="tg-office-title"><header><div><span className="eyebrow">UNIQUE STRATEGIC PROPERTY</span><h2 id="tg-office-title">Manage Telegram Office</h2></div><button aria-label="Close office management" onClick={()=>setShowOffice(false)}>×</button></header>{notice&&<p role="status">{notice}</p>}{(data.office.can_operate||data.office.can_manage)&&<TelegramOfficeControls office={data.office} send={async(a,p)=>!!await act(a,p,"telegram_manage")} admin={data.office.can_manage}/>}</dialog>
 </div>;
}

