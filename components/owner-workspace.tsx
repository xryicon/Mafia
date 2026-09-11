"use client";
import {useState} from "react";
import Link from "next/link";
import {StaffPanel,type StaffState} from "@/components/staff-panel";
import {TelegramAdmin} from "@/components/telegram-admin";
import {DistrictOwner} from "@/components/district-owner";
import {MiningOwner} from "@/components/mining-owner";
import {SeasonPanel} from "@/components/season-panel";
import type {SeasonState} from "@/lib/seasons";
export const ownerSections=[["overview","Control room"],["moderation","Player moderation"],["roles","Roles & permissions"],["districts","Districts & properties"],["mines","Mines & Quarries"],["telegrams","Telegram Office"],["economy","Economy & production"],["adjustments","Money & assets"],["seasons","Seasons & leaderboards"],["tickets","Support tickets"],["evidence","Sanctions & evidence"],["chat","Chat moderation"],["audit","Audit history"]];
export function OwnerWorkspace({staff,seasons,initialSection="overview"}:{staff:StaffState;seasons:SeasonState;initialSection?:string}){
 const [section,setSection]=useState(ownerSections.some(([id])=>id===initialSection)?initialSection:"overview"),[staffData,setStaff]=useState(staff),[seasonData,setSeasons]=useState(seasons);
 if(!staffData.permissions.includes("roles.manage"))return <div className="control-layout"><h1>Owner access required</h1><Link href="/dashboard">Return to empire</Link></div>;
 return <div className="owner-workspace"><aside className="owner-sidebar"><p className="eyebrow">PRIVATE OFFICE</p><h2>The city is yours<br/>to govern.</h2><nav aria-label="Owner navigation">{ownerSections.map(([id,label],i)=><button key={id} className={section===id?"active":""} aria-current={section===id?"page":undefined} onClick={()=>setSection(id)}><span>{String(i+1).padStart(2,"0")}</span>{label}</button>)}</nav><Link href="/dashboard">← Return to empire</Link></aside><div className="owner-main"><header className="owner-heading"><p className="eyebrow">BLACKWATER / OWNER OFFICE</p><h1>Owner panel</h1><p>Every control in one place. Every important action recorded.</p></header>
 {section==="overview"?<section className="owner-overview"><div className="owner-welcome"><span className="tag">OWNER ACCESS</span><h2>One office.<br/>Every control.</h2><p>Shape the economy, support your players and write the next chapter of Blackwater.</p><Link href="/seasons">{seasonData.season.name} · {seasonData.season.status} ↗</Link></div><div className="owner-shortcuts">{ownerSections.slice(1).map(([id,label],i)=><button key={id} onClick={()=>setSection(id)}><span>{String(i+2).padStart(2,"0")}</span><strong>{label}</strong><small>Open controls ↗</small></button>)}</div></section>:section==="telegrams"?<TelegramAdmin/>:section==="districts"?<DistrictOwner/>:section==="mines"?<MiningOwner/>:section==="seasons"?<SeasonPanel initial={seasonData} management embedded onChange={setSeasons}/>:<StaffPanel key={section} initial={staffData} section={section} embedded onChange={setStaff}/>}
 </div></div>;
}
