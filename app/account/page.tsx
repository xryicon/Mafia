import Link from "next/link";
import {requireUser} from "@/lib/auth";
import {createClient} from "@/lib/supabase/server";
import {UsernameForm} from "@/components/username-form";
import {LogoutButton} from "@/components/logout-button";
import type {SocialState} from "@/lib/social";
export const dynamic="force-dynamic";
export const metadata={title:"Your account"};
export default async function Account(){
 await requireUser("/account");
 const {data,error}=await (await createClient()).rpc("social_state");if(error||!data)throw new Error("Account could not be loaded.");
 const identity=data as SocialState;
 return <div className="control-layout account-page"><p className="eyebrow">YOUR BLACKWATER IDENTITY</p><h1>Your account.</h1><section className="control-card"><h2>{identity.username_claimed?identity.username:"Choose your username"}</h2>{identity.username_claimed?<p>Your name appears in chat, the market and rankings. For a name change, <Link href="/support">open a Support ticket</Link>.</p>:<UsernameForm/>}<Link className="button ghost" href="/update-password">Change password</Link><LogoutButton/></section></div>;
}
