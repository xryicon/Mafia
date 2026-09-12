import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {InventoryWorkspace} from "@/components/inventory-workspace";
import type {InventoryState} from "@/lib/inventory";
export const dynamic="force-dynamic";
export const metadata={title:"Inventory"};
export default async function Inventory(){await requireUser("/inventory");const r=await(await createClient()).rpc("inventory_state",{p_offset:0});if(r.error||!r.data)throw new Error("Inventory could not be loaded. Please refresh.");return <InventoryWorkspace initial={r.data as InventoryState}/>;}
