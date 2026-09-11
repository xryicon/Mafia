import {GamePage} from "@/components/game-page";
export const dynamic="force-dynamic";
export const metadata={title:"Properties"};
export default async function Properties({searchParams}:{searchParams:Promise<{good?:string}>}){
 return <GamePage path="/properties" view="businesses" good={(await searchParams).good}/>;
}
