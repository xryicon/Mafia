import {DistrictPage} from "@/components/district-page";
export default async function Page({params}:{params:Promise<{districtId:string}>}){const {districtId}=await params;return <DistrictPage slug={districtId}/>;}
