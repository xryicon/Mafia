import {redirect} from "next/navigation";
import {requireUser} from "@/lib/auth";
export const dynamic="force-dynamic";
export default async function Profile(){const user=await requireUser("/profile");redirect("/players/"+user.id);}
