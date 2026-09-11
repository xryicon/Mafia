"use client";
import Link from "next/link";
import {useEffect,useState} from "react";
import {useMining} from "./use-mining";
import {MineControls} from "./mine-controls";
import {mineStatus} from "@/lib/mining";
import {GameIcon} from "./game-icon";
export function MiningOwner(){
 const mining=useMining(),{data,notice,failed,busy,act}=mining,[selected,setSelected]=useState("");
 useEffect(()=>setSelected(new URLSearchParams(location.search).get("mine")??""),[]);
 if(!data)return <section className="control-card"><h2>Mines & Quarries</h2><p>{notice||"Loading the city mining registry…"}</p><button className="button" onClick={mining.refresh}>Refresh mines</button></section>;
 if(!data.can_manage)return <p>Owner mining permission is required.</p>;
 const site=data.sites.find(s=>s.id===selected)??data.sites[0];
 return <div className="mining-owner"><p className="eyebrow">CITY MINING AUTHORITY</p><h2>Mines & Quarries</h2><p>Open sites, allow public mining, configure extraction and auction city-owned claims.</p><Link className="market-outline" href="/districts/mines-and-quarries">View mining district →</Link>
 {notice&&<div className={"mine-notice "+(failed?"error":"")} role={failed?"alert":"status"}>{notice}{mining.retry&&<button disabled={mining.working} className="market-outline" onClick={()=>void mining.retryAction()}>Retry same request</button>}</div>}
 <div className="mine-admin-grid"><nav className="mine-admin-list command-panel" aria-label="Mine management sites">{data.sites.map(m=><button key={m.id} className={site?.id===m.id?"active":""} onClick={()=>setSelected(m.id)}><GameIcon name="pickaxe" size={20}/><span>{m.code} · {m.name}<small>{mineStatus(m)}</small></span></button>)}</nav>
 {site&&<MineControls key={site.id} site={site} data={data} busy={busy} act={act}/>}</div>
 <p className="mine-help">Pickaxe condition, respect and auction limits are editable in Economy & production.</p>
 </div>;
}

