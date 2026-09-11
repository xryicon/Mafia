import {GamePage} from "@/components/game-page";
export const dynamic="force-dynamic";
export const metadata={title:"Financial history"};
export default function Ledger(){return <GamePage path="/ledger" view="ledger"/>;}
