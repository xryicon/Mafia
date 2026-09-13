import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {SkillsWorkspace} from "@/components/skills-workspace";
import type {SkillsState} from "@/lib/skills";
export const dynamic="force-dynamic";
export const metadata={title:"Skills"};
export default async function SkillsPage({searchParams}:{searchParams:Promise<{skill?:string}>}){await requireUser("/skills");const [r,params]=await Promise.all([(await createClient()).rpc("skills_state"),searchParams]);if(r.error||!r.data)throw new Error("Your skills could not load. Please refresh.");return <SkillsWorkspace initial={r.data as SkillsState} initialSkill={params.skill}/>;}
