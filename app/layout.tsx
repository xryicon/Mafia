import type {Metadata} from "next";
import {SiteChrome} from "@/components/site-chrome";
import "./globals.css";
import "./confirmation.css";
import "./districts.css";
import "./telegrams.css";
import "./dashboard.css";
import "./bin-diving.css";
import "./refineries.css";
import "./operations.css";
import "./bank.css";
import "./inventory.css";
import "./player-profile.css";
import "./market.css";
import "./commodities.css";
import "./mining.css";
import "./mining.css";
export const metadata:Metadata={
 metadataBase:new URL("https://mafia.xryicon.workers.dev"),
 title:{default:"Blackwater Mafia — A player-driven crime economy",template:"%s · Blackwater Mafia"},
 description:"Enter Blackwater Mafia. Build businesses, produce goods, trade with real players, and turn your first deal into an empire. Play directly in your browser.",
 openGraph:{title:"Blackwater Mafia",description:"The city runs on deals. Make yours count.",images:[{url:"/art/harbor.webp",width:1680,height:945,alt:"The harbor city of Blackwater"}],type:"website"},
 twitter:{card:"summary_large_image",title:"Blackwater Mafia",description:"A city built on ambition. An economy built by players.",images:["/art/harbor.webp"]},
 icons:{icon:"/icon.svg"}
};
export default function RootLayout({children}:Readonly<{children:React.ReactNode}>){return <html lang="en"><body><a className="skip" href="#main">Skip to content</a><SiteChrome>{children}</SiteChrome></body></html>;}
