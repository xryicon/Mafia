import {GamePage} from "@/components/game-page";
export const dynamic="force-dynamic";
export const metadata={title:"Dashboard"};
export default async function Dashboard({searchParams}:{searchParams:Promise<{view?:string}>}){
 const {view}=await searchParams;return <GamePage path="/dashboard" view={view==="ledger"?"ledger":"overview"}/>;
}
