import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {CraftingWorkspace} from "@/components/crafting-workspace";
export const dynamic="force-dynamic";
export const metadata={title:"Crafting station"};
export default async function Crafting({searchParams}:{searchParams:Promise<{building?:string;recipe?:string}>}){
 const q=await searchParams;await requireUser("/crafting"+(q.building?"?building="+encodeURIComponent(q.building):""));
 const r=await(await createClient()).rpc("crafting_state",{p_building:q.building??null});
 if(r.error||!r.data)throw new Error("Crafting could not load. Please refresh.");
 return <CraftingWorkspace initial={r.data} initialRecipe={q.recipe}/>;
}
