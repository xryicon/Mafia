import {GamePage} from "@/components/game-page";
export const dynamic="force-dynamic";
export const metadata={title:"Market"};
export default async function Market({searchParams}:{searchParams:Promise<{view?:string;good?:string;district?:string}>}){
 const {view,good,district}=await searchParams;return <GamePage path="/market" view={view==="inventory"?"inventory":"market"} good={good} district={district}/>;
}
