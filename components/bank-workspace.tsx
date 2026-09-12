"use client";
import {useEffect,useRef,useState,type ReactNode} from "react";
import Link from "next/link";
import {GameIcon} from "@/components/game-icon";
import {useBank} from "@/components/use-bank";
import {money} from "@/lib/game";
import type {BankState} from "@/lib/bank";
type Kind="deposit"|"withdraw";
function Panel({title,children,className="",extra}:{title:string;children:ReactNode;className?:string;extra?:ReactNode}){return <section className={"bank-panel "+className}><header><h2>{title}</h2>{extra}</header>{children}</section>;}
function Transfer({kind,seasonId,h,close}:{kind:Kind;seasonId:string;h:ReturnType<typeof useBank>;close:()=>void}){
 const dialog=useRef<HTMLDialogElement>(null),[amount,setAmount]=useState("");
 useEffect(()=>{dialog.current?.showModal();},[]);
 const n=Number(amount),deposit=kind==="deposit",d=h.data,available=deposit?d.player.cash:d.balance,maximum=Math.min(available,d.settings.bank_max_transfer);
 const valid=Number.isSafeInteger(n)&&n>0&&n<=maximum&&d.playable&&d.season.id===seasonId&&(!deposit||d.settings.bank_deposits_enabled===1);
 return <dialog className="command-modal bank-dialog" ref={dialog} onCancel={e=>{if(h.working||h.retry)e.preventDefault();else close();}} aria-labelledby="bank-transfer-title">
 <button className="bank-close" aria-label="Close transfer" disabled={h.working||!!h.retry} onClick={close}>×</button><p className="bank-eyebrow">NATIONAL BANK / YOUR MONEY</p><h2 id="bank-transfer-title">{deposit?"Deposit funds":"Withdraw funds"}</h2>
 <p>{deposit?"Move money from your wallet into your bank account.":"Move money from your bank account into your wallet."}</p>
 <form onSubmit={async e=>{e.preventDefault();if(valid&&!h.busy&&await h.transfer({action:kind,payload:{season_id:seasonId,request_id:crypto.randomUUID(),amount:n}}))close();}}>
 <label>Amount ($)<input autoFocus type="number" inputMode="numeric" min={1} max={maximum} step={1} required value={amount} disabled={h.busy} onChange={e=>setAmount(e.target.value)}/></label>
 <div className="bank-amount-tools"><span>{money(available)} available</span><button type="button" disabled={h.busy||maximum<1} onClick={()=>setAmount(String(maximum))}>Use maximum</button></div>
 <dl className="bank-facts"><div><dt>Transfer fee</dt><dd>{money(0)}</dd></div><div><dt>Cash after transfer</dt><dd>{valid?money(d.player.cash+(deposit?-n:n)):"—"}</dd></div><div><dt>Bank balance after transfer</dt><dd>{valid?money(d.balance+(deposit?n:-n)):"—"}</dd></div></dl>
 <p className="bank-help">Up to {money(d.settings.bank_max_transfer)} per transfer. Deposits belong to this season.</p>
 {h.notice&&<p className={"bank-notice "+(h.failed?"error":"")} role={h.failed?"alert":"status"}>{h.notice}</p>}
 {h.retry?<button className="bank-gold" type="button" disabled={h.working} onClick={async()=>{if(await h.retryTransfer())close();}}>Retry transfer safely <GameIcon name="refresh" size={18}/></button>:<button className="bank-gold" disabled={!valid||h.busy}>{h.working?"Confirming…":deposit?"Confirm deposit":"Confirm withdrawal"} <GameIcon name="arrow" size={18}/></button>}
 </form></dialog>;
}
export function BankWorkspace({initial}:{initial:BankState}){
 const h=useBank(initial),d=h.data,[transfer,setTransfer]=useState<{kind:Kind;seasonId:string}|null>(null);
 const [tab,setTab]=useState("overview");const history=useRef<HTMLDivElement>(null);
 const open=(kind:Kind)=>{if(!h.busy)setTransfer({kind,seasonId:d.season.id});};
 const depositsOpen=d.playable&&d.settings.bank_deposits_enabled===1;
 const maxFlow=Math.max(1,...d.flow.flatMap(x=>[x.deposits,x.withdrawals]));
 const flowIn=d.flow.reduce((a,x)=>a+x.deposits,0),flowOut=d.flow.reduce((a,x)=>a+x.withdrawals,0);
 return <div className="bank-page" data-feature="national-bank">
 <div className="bank-topline"><Link href="/dashboard">← Dashboard</Link><span>/ NATIONAL BANK</span>{d.can_manage&&<Link href="/owner?section=economy">Bank settings in Owner panel ↗</Link>}</div>
 <div className="bank-main-grid">
 <section className="bank-hero"><img className="bank-hero-art" src="/art/national-bank.webp" srcSet="/art/national-bank-small.webp 768w, /art/national-bank.webp 1672w" sizes="(max-width:850px) 100vw, 75vw" alt="Blackwater National Bank, its illuminated stone columns overlooking the harbor." width={1672} height={941} fetchPriority="high"/><div className="bank-hero-copy"><p className="bank-eyebrow">BLACKWATER / FINANCIAL DISTRICT</p><h1>National Bank</h1><p className="bank-hero-subtitle">CAPITAL. CONFIDENCE. POWER.</p><span className="bank-rule"/><h2>More than money.<br/>A stronger tomorrow.</h2><p>Your next move starts with a reserve. Deposit your earnings, keep cash ready for a deal, and build your place in Blackwater.</p></div><div className="bank-hero-foot"><GameIcon name="bank" size={23}/><span>TRUST FUNDS AMBITION.</span><small>EST. BLACKWATER</small></div></section>
 <aside className="bank-account bank-panel"><header><div><h2>National Bank</h2><p>{d.season.name}</p></div><span className={"bank-status "+(d.playable?"open":"")}>{d.playable?"OPEN":"SEASON CLOSED"}</span></header>
 <nav className="bank-tabs" aria-label="Bank sections"><button aria-pressed={tab==="overview"} onClick={()=>setTab("overview")}>Overview</button><button aria-pressed={tab==="statement"} onClick={()=>{setTab("statement");history.current?.scrollIntoView({behavior:"smooth",block:"start"});}}>Statement</button><Link href="/ledger">Ledger ↗</Link></nav>
 <p className="bank-eyebrow">ACCOUNT SUMMARY</p><div className="bank-balance"><span>Bank balance</span><strong>{money(d.balance)}</strong><small>Held for {d.player.handle}</small></div>
 <dl className="bank-facts"><div><dt><GameIcon name="cash" size={18}/>Cash on hand</dt><dd>{money(d.player.cash)}</dd></div><div><dt><GameIcon name="bank" size={18}/>Bank + wallet</dt><dd>{money(d.player.cash+d.balance)}</dd></div><div><dt><GameIcon name="ledger" size={18}/>Transfers this season</dt><dd>{d.totals.transfers.toLocaleString()}</dd></div><div><dt><GameIcon name="shield" size={18}/>Transfer fees</dt><dd>No fee</dd></div><div><dt>Account status</dt><dd>{d.opened_at?"Active":"Ready to open"}</dd></div></dl>
 <div className="bank-account-actions"><button className="bank-gold" disabled={h.busy||!depositsOpen||d.player.cash<1} onClick={()=>open("deposit")}><span aria-hidden="true">↓</span> Deposit funds</button><button className="bank-outline" disabled={h.busy||!d.playable||d.balance<1} onClick={()=>open("withdraw")}><span aria-hidden="true">↑</span> Withdraw funds</button></div>
 <p className="bank-help">{!d.playable?"Transfers resume when the season opens.":!depositsOpen?"New deposits are paused. You can still withdraw your balance.":"Your first deposit opens your account. Withdraw to your wallet whenever you need to trade."}</p>
 <button className="bank-refresh" disabled={h.working||h.reading} onClick={()=>h.refresh()}>Refresh balances <GameIcon name="refresh" size={16}/></button></aside>
 </div>
 {h.notice&&!transfer&&<div className={"bank-notice "+(h.failed?"error":"")} role={h.failed?"alert":"status"}>{h.notice}</div>}
 <div className="bank-lower-grid">
 <Panel title="Banking services" className="bank-services"><button onClick={()=>open("deposit")} disabled={h.busy||!depositsOpen||d.player.cash<1}><GameIcon name="bank" size={31}/><span><strong>Personal deposits</strong><small>Build a reserve for your next move.</small></span><GameIcon name="arrow" size={17}/></button><button onClick={()=>open("withdraw")} disabled={h.busy||!d.playable||d.balance<1}><GameIcon name="cash" size={31}/><span><strong>Cash withdrawals</strong><small>Put your money back to work.</small></span><GameIcon name="arrow" size={17}/></button><Link href="/market"><GameIcon name="trade" size={31}/><span><strong>Player exchange</strong><small>Buy resources. Back your business.</small></span><GameIcon name="arrow" size={17}/></Link><p className="bank-help">Loans, mortgages and bonds are not yet offered.</p></Panel>
 <div ref={history} className="bank-statement" id="bank-statement"><Panel title="Your transactions" extra={<span className="bank-period">THIS SEASON</span>}>
 {d.history.length?<><div className="bank-table-scroll"><table><thead><tr><th>Date</th><th>Type</th><th>Amount</th><th>Bank balance</th></tr></thead><tbody>{d.history.map(e=><tr key={e.id}><td><time dateTime={e.created_at}>{new Date(e.created_at).toLocaleDateString("en-GB",{day:"numeric",month:"short",timeZone:"UTC"})}<small>{new Date(e.created_at).toLocaleTimeString("en-GB",{hour:"2-digit",minute:"2-digit",timeZone:"UTC"})} UTC</small></time></td><td>{e.delta>0?"Deposit":"Withdrawal"}</td><td className={e.delta>0?"bank-in":"bank-out"}>{e.delta>0?"+":"−"}{money(Math.abs(e.delta))}</td><td>{money(e.balance_after)}</td></tr>)}</tbody></table></div><div className="bank-pagination"><button disabled={h.reading||d.offset===0} onClick={()=>h.refresh(Math.max(0,d.offset-d.page_size))}>← Previous</button><span>Page {Math.floor(d.offset/d.page_size)+1} of {Math.max(1,Math.ceil(d.total/d.page_size))}</span><button disabled={h.reading||d.offset+d.page_size>=d.total} onClick={()=>h.refresh(d.offset+d.page_size)}>Next →</button></div></>:<div className="bank-empty"><GameIcon name="ledger" size={37}/><h3>Your first chapter starts here.</h3><p>Deposits and withdrawals will appear here as you use the bank.</p></div>}
 <Link className="bank-text-link" href="/ledger">View full wallet ledger <GameIcon name="arrow" size={17}/></Link></Panel></div>
 <Panel title="Your reserve flow" className="bank-flow" extra={<span className="bank-period">7 DAYS · UTC</span>}><div className="bank-chart" role="img" aria-label={"Your last seven days: "+money(flowIn)+" deposited, "+money(flowOut)+" withdrawn."}>{d.flow.map(x=><div key={x.day} className="bank-chart-day"><div className="bank-chart-bars"><span className="bank-bar-in" style={{height:100*x.deposits/maxFlow+"%"}} title={x.day+": "+money(x.deposits)+" deposited"}/><span className="bank-bar-out" style={{height:100*x.withdrawals/maxFlow+"%"}} title={x.day+": "+money(x.withdrawals)+" withdrawn"}/></div><small>{new Date(x.day+"T12:00:00Z").toLocaleDateString("en-GB",{weekday:"short",timeZone:"UTC"})}</small></div>)}</div>
 <div className="bank-flow-totals"><div><span>Deposited</span><strong className="bank-in">{money(flowIn)}</strong></div><div><span>Withdrawn</span><strong className="bank-out">{money(flowOut)}</strong></div></div><p className="bank-help">Your transfers only. Money held in the bank continues to count toward net worth.</p><blockquote>“Every fortune needs a foundation.”</blockquote></Panel>
 </div>{transfer&&<Transfer kind={transfer.kind} seasonId={transfer.seasonId} h={h} close={()=>setTransfer(null)}/>}</div>;
}
