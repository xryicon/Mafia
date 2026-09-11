import Link from "next/link";
import {notFound} from "next/navigation";
import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import type {Ranking} from "@/lib/seasons";
export const dynamic="force-dynamic";
export const metadata={title:"Player profile"};
export default async function Profile({params}:{params:Promise<{id:string}>}){
 await requireUser();const {id}=await params;
 if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(id))notFound();
 const {data,error}=await (await createClient()).rpc("season_profile",{p_player:id});if(error||!data)notFound();
 const current=data.current as Ranking[],previous=data.previous as Ranking[];
 return <div className="control-layout"><div className="control-heading"><div><p className="eyebrow">BLACKWATER / PLAYER PROFILE</p><h1>{data.handle}</h1></div><Link className="button ghost" href="/seasons">Leaderboards</Link></div>
 <h2>{data.current_season}</h2><div className="control-grid">{current.map(r=><article className="control-card" key={r.metric}><p>{r.label}</p><strong className="hall-place">#{r.rank}</strong><p>{Number(r.score).toLocaleString("en-US")}</p></article>)}</div>{!current.length&&<p>No current-season ranking yet.</p>}
 <h2>Previous seasons</h2><div className="control-grid">{previous.map(r=><article className="control-card" key={String(r.season_id)+String(r.metric)}><p className="eyebrow">{r.season_name}</p><h3>{r.label} · #{r.rank}</h3><p>{Number(r.score).toLocaleString("en-US")}</p></article>)}</div>{!previous.length&&<p>Archived rankings will appear after the first season ends.</p>}
 <h2>Hall of Fame</h2><p>{data.hall_of_fame.length} archived award{data.hall_of_fame.length===1?"":"s"}</p></div>;
}
