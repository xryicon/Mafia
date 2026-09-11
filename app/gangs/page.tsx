import Link from "next/link";
import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {Artwork} from "@/components/artwork";
import {GameIcon} from "@/components/game-icon";
import type {GangState} from "@/lib/city";
export const dynamic="force-dynamic";
export const metadata={title:"Gangs"};
export default async function Gangs(){
 await requireUser("/gangs");const {data,error}=await (await createClient()).rpc("gang_directory");if(error||!data)throw new Error("The gang register could not be loaded.");
 const state=data as GangState;
 return <div className="gang-world"><section className="estate-hero"><Artwork name="harbor" priority/><div className="estate-hero-shade"/><div className="estate-hero-copy"><p className="eyebrow">BLACKWATER <span>›</span> GANGS</p><h1>The city's families.</h1><p className="estate-location">{state.season.name.toUpperCase()}</p><i className="estate-gold-rule"/><p className="estate-motto">A name is earned. A family is built.</p><p className="estate-description">The seasonal gang register. Follow the crews, their respect, and their contribution to Blackwater.</p></div></section><div className="estate-body"><section className="estate-panel gang-register"><div className="estate-panel-title"><GameIcon name="people"/><h2>Gang standings</h2><span>{state.total} registered</span></div>{state.gangs.length?<div className="table-scroll"><table className="market-table"><thead><tr><th>Rank</th><th>Gang</th><th>Members</th><th>Respect</th><th>Contribution</th></tr></thead><tbody>{state.gangs.map(g=><tr key={g.id}><td>#{g.rank}</td><td>{g.name}{g.joined&&<span className="tag">YOUR GANG</span>}</td><td>{g.members}</td><td>{Number(g.respect).toLocaleString("en-US")}</td><td>{Number(g.contribution).toLocaleString("en-US")}</td></tr>)}</tbody></table></div>:<div className="gang-empty"><GameIcon name="people" size={52}/><h2>Every empire starts with a circle.</h2><p>No gangs are registered this season. Get to know the players making their name in Blackwater.</p><Link className="button" href="/players">Meet the players <GameIcon name="arrow" size={17}/></Link><Link className="estate-text-link" href="/seasons">View season standings →</Link></div>}</section></div></div>;
}
