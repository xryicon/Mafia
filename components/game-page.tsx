import Link from "next/link";
import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {GameShell} from "@/components/game-shell";
import {LogoutButton} from "@/components/logout-button";
import type {GameView} from "@/lib/city";
import type {GameState} from "@/lib/game";
export async function GamePage({path,view,good}:{path:string;view:GameView;good?:string}){
 await requireUser(path);const {data,error}=await (await createClient()).rpc("game_state");
 if(error||!data)return <div className="control-layout"><h1>The city could not be loaded</h1><p>Sign in again to restore your session. Contact the game Owner if your access remains restricted.</p><LogoutButton/><Link href="/login">Sign in</Link></div>;
 const state=data as GameState;
 return <GameShell initial={state} initialTab={view} initialGood={state.goods.some(g=>g.id===good)?good:undefined}/>;
}
