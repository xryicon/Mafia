"use client";
import Link from "next/link";
import {usePathname} from "next/navigation";
import {CityChrome} from "@/components/city-chrome";
import {Brand} from "@/components/brand";
export function SiteChrome({children}:{children:React.ReactNode}){
 const path=usePathname(),game=["/bin-diving","/telegrams","/ledger","/dashboard","/market","/properties","/districts","/gangs","/profile","/players","/seasons","/owner","/staff","/support","/community","/account"].some(p=>path===p||path.startsWith(p+"/")),home=path==="/",auth=["/login","/signup","/forgot-password","/update-password"].includes(path);
 if(path==="/auth/confirmed")return <main id="main" className="confirmation-frame">{children}</main>;
 if(game)return <CityChrome>{children}</CityChrome>;
 return <div className={home?"public-world":auth?"auth-world":"inner-world"}><header className={"bw-header "+(home?"over-hero":"")}><Brand/><nav aria-label="Main navigation">{home&&<><a className="header-explore" href="#economy">The economy</a><a className="header-explore" href="#city">The city</a></>}<Link href="/login">Log in</Link><Link className="button small" href="/signup">Join Blackwater <span aria-hidden="true">↗</span></Link></nav></header><main id="main">{children}</main><footer className="bw-footer"><Brand/><p>A city of ambition.<br/>An economy of your making.</p><div><Link href="/signup">Create account</Link><Link href="/login">Log in</Link></div><small>BLACKWATER MAFIA · FICTIONAL GAME CURRENCY<br/>A PLAYER-DRIVEN BROWSER STRATEGY GAME</small></footer></div>;
}
