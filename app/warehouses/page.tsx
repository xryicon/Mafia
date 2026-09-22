import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {WarehouseOverview} from "@/components/warehouse-overview";
import type {InventoryState} from "@/lib/inventory";
export const dynamic="force-dynamic";
export const metadata={title:"Warehouses"};
export default async function Warehouses(){await requireUser("/warehouses");const r=await(await createClient()).rpc("inventory_state",{p_offset:0});if(r.error||!r.data)throw new Error("Warehouses could not be loaded. Please refresh.");return <WarehouseOverview initial={r.data as InventoryState}/>;}
