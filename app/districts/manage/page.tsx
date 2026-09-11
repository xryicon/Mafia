import {requireUser} from "@/lib/auth";
import {DistrictOwner} from "@/components/district-owner";
export default async function Page({searchParams}:{searchParams:Promise<{district?:string}>}){await requireUser("/districts");return <DistrictOwner initialSlug={(await searchParams).district}/>;}
