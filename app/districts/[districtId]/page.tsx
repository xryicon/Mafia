import {DistrictPage} from "@/components/district-page";
export default async function Page({params,searchParams}:{params:Promise<{districtId:string}>;searchParams:Promise<{registry?:string}>}){const {districtId}=await params,{registry}=await searchParams;return <DistrictPage slug={districtId} registry={registry==="1"}/>;}
